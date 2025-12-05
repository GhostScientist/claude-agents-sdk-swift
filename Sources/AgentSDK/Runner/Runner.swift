import Foundation

// MARK: - Runner

/// Executes agents by managing the conversation loop, tool calls, and handoffs.
///
/// `Runner` is the core execution engine of AgentSDK. It takes an agent and user input,
/// then manages the back-and-forth with the LLM until the agent produces a final response
/// or a terminal condition is reached (max turns, cancellation, or error).
///
/// ## Overview
///
/// The runner handles:
/// - Building and sending requests to the LLM provider
/// - Processing streaming responses in real-time
/// - Executing tool calls and feeding results back to the LLM
/// - Managing handoffs between agents
/// - Enforcing input/output guardrails
/// - Tracking token usage and conversation history
///
/// ## Basic Usage
///
/// ```swift
/// import AgentSDK
/// import ClaudeProvider
///
/// let provider = ClaudeProvider(apiKey: "your-api-key")
/// let runner = Runner(provider: provider)
///
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "You are a helpful assistant."
/// )
///
/// // Run to completion
/// let result = try await runner.run(agent, input: "Hello!")
/// print(result.output)
/// ```
///
/// ## Streaming Responses
///
/// For real-time UI updates, use the streaming API:
///
/// ```swift
/// for try await event in runner.stream(agent, input: "Tell me a story") {
///     switch event {
///     case .textDelta(let text):
///         print(text, terminator: "")
///     case .toolCallStarted(let name, _):
///         print("\n[Calling: \(name)]")
///     case .completed(let result):
///         print("\n\nTokens used: \(result.tokenUsage?.totalTokens ?? 0)")
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Multi-Turn Conversations
///
/// By default, the runner allows up to 10 turns (LLM calls) per execution.
/// Each tool call response triggers a new turn. Configure this limit:
///
/// ```swift
/// let runner = Runner(provider: provider, maxTurns: 20)
/// ```
///
/// ## Thread Safety
///
/// `Runner` is implemented as an actor, ensuring thread-safe access to its state.
/// Multiple agents can be run concurrently, and all active tasks can be cancelled
/// using ``cancelAll()``.
///
/// ## Topics
///
/// ### Creating a Runner
/// - ``init(provider:maxTurns:)``
///
/// ### Running Agents
/// - ``run(_:input:context:)``
/// - ``stream(_:input:context:)``
///
/// ### Managing Execution
/// - ``cancelAll()``
public actor Runner {
    private let provider: any LLMProvider
    private let maxTurns: Int
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    /// Creates a new runner with the specified LLM provider.
    ///
    /// - Parameters:
    ///   - provider: The LLM provider to use for generating responses.
    ///   - maxTurns: Maximum number of LLM calls per execution. Defaults to 10.
    ///               Each tool call response triggers a new turn.
    public init(provider: any LLMProvider, maxTurns: Int = 10) {
        self.provider = provider
        self.maxTurns = maxTurns
    }

    // MARK: - Run to Completion

    /// Runs an agent to completion and returns the final result.
    ///
    /// This method executes the agent loop, handling all tool calls and handoffs
    /// automatically, until the agent produces a final text response.
    ///
    /// - Parameters:
    ///   - agent: The agent to execute.
    ///   - input: The user's input message.
    ///   - context: Optional context for state management. Defaults to empty.
    /// - Returns: A ``RunResult`` containing the output and execution metadata.
    /// - Throws: ``AgentError`` if execution fails, input is blocked, or max turns exceeded.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await runner.run(agent, input: "What's 2 + 2?")
    /// print("Answer: \(result.output)")
    /// print("Tool calls made: \(result.toolCallCount)")
    /// ```
    public func run<A: AgentProtocol>(
        _ agent: A,
        input: String,
        context: A.Context = A.Context()
    ) async throws -> RunResult {
        var result: RunResult?

        for try await event in stream(agent, input: input, context: context) {
            if case .completed(let runResult) = event {
                result = runResult
            }
        }

        guard let finalResult = result else {
            throw AgentError.unknown(NSError(domain: "AgentSDK", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Agent completed without result"
            ]))
        }

        return finalResult
    }

    // MARK: - Streaming

    /// Streams agent execution events for real-time processing.
    ///
    /// This method returns an async stream of ``AgentEvent``s, allowing you to
    /// react to each step of the agent's execution as it happens. This is ideal
    /// for building responsive UIs that show typing indicators, tool usage, etc.
    ///
    /// - Parameters:
    ///   - agent: The agent to execute.
    ///   - input: The user's input message.
    ///   - context: Optional context for state management. Defaults to empty.
    /// - Returns: An async throwing stream of ``AgentEvent``s.
    ///
    /// ## Events
    ///
    /// The stream emits events in order:
    /// 1. ``AgentEvent/agentStarted(name:)`` - Agent begins processing
    /// 2. ``AgentEvent/textDelta(_:)`` - Incremental text from the LLM
    /// 3. ``AgentEvent/toolCallStarted(name:arguments:)`` - Tool invocation begins
    /// 4. ``AgentEvent/toolCallCompleted(name:result:isError:)`` - Tool returns result
    /// 5. ``AgentEvent/handoff(from:to:reason:)`` - Control transfers to another agent
    /// 6. ``AgentEvent/completed(_:)`` - Final result available
    ///
    /// ## Example
    ///
    /// ```swift
    /// for try await event in runner.stream(agent, input: "Search for Swift tutorials") {
    ///     switch event {
    ///     case .agentStarted(let name):
    ///         print("[\(name) is thinking...]")
    ///     case .textDelta(let text):
    ///         print(text, terminator: "")
    ///     case .toolCallStarted(let name, _):
    ///         print("\n🔧 Using \(name)...")
    ///     case .toolCallCompleted(let name, _, let isError):
    ///         print(isError ? "❌ \(name) failed" : "✅ \(name) done")
    ///     case .handoff(_, let to, let reason):
    ///         print("\n→ Handing off to \(to): \(reason)")
    ///     case .completed(let result):
    ///         print("\n\nDone! Used \(result.tokenUsage?.totalTokens ?? 0) tokens")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public func stream<A: AgentProtocol>(
        _ agent: A,
        input: String,
        context: A.Context = A.Context()
    ) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let taskId = UUID()
            let task = Task {
                do {
                    try await self.executeAgentLoop(
                        agent: agent,
                        input: input,
                        context: context,
                        continuation: continuation
                    )
                } catch {
                    if let agentError = error as? AgentError {
                        continuation.yield(.error(agentError))
                    } else {
                        continuation.yield(.error(.unknown(error)))
                    }
                    continuation.finish(throwing: error)
                }
            }

            Task {
                await self.trackTask(taskId, task: task)
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.removeTask(taskId)
                }
            }
        }
    }

    // MARK: - Agent Loop

    private func executeAgentLoop<A: AgentProtocol>(
        agent: A,
        input: String,
        context: A.Context,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async throws {
        var currentAgent: AnyAgent = AnyAgent(agent)
        var messages: [Message] = []
        var turnCount = 0
        var toolCallCount = 0
        var totalUsage: TokenUsage?
        var agentHistory: [String] = []

        // Validate input with guardrails
        var processedInput = input
        for guardrail in currentAgent.inputGuardrails {
            let result = try await guardrail.validate(processedInput, context: context)
            continuation.yield(.guardrailTriggered(name: guardrail.name, result: result))

            switch result {
            case .passed:
                continue
            case .modified(let newContent, _):
                processedInput = newContent
            case .blocked(let reason):
                throw AgentError.inputBlocked(guardrail: guardrail.name, reason: reason)
            }
        }

        // Build initial messages
        messages.append(.system(currentAgent.instructions))
        messages.append(.user(processedInput))

        continuation.yield(.agentStarted(name: currentAgent.name))
        agentHistory.append(currentAgent.name)

        // Agent loop
        while turnCount < maxTurns {
            try Task.checkCancellation()

            turnCount += 1

            // Build tool definitions (tools + handoffs)
            var toolDefs = currentAgent.tools.map { ToolDefinition(from: $0) }
            toolDefs += currentAgent.handoffs.map { $0.toolDefinition }

            // Make LLM request
            let request = LLMRequest(
                model: currentAgent.model ?? provider.defaultModel,
                messages: messages,
                tools: toolDefs.isEmpty ? nil : toolDefs
            )

            // Stream response
            var responseContent = ""
            var responseToolCalls: [ToolCall] = []

            for try await event in provider.stream(request) {
                switch event {
                case .textDelta(let delta):
                    responseContent += delta
                    continuation.yield(.textDelta(delta))

                case .toolCallStart(let id, let name):
                    responseToolCalls.append(ToolCall(id: id, name: name, arguments: ""))

                case .toolCallDelta(let id, let argsDelta):
                    if let index = responseToolCalls.firstIndex(where: { $0.id == id }) {
                        let existing = responseToolCalls[index]
                        responseToolCalls[index] = ToolCall(
                            id: id,
                            name: existing.name,
                            arguments: existing.arguments + argsDelta
                        )
                    }

                case .toolCallComplete:
                    break

                case .done(let response):
                    if let usage = response.usage {
                        if let existing = totalUsage {
                            totalUsage = TokenUsage(
                                inputTokens: existing.inputTokens + usage.inputTokens,
                                outputTokens: existing.outputTokens + usage.outputTokens
                            )
                        } else {
                            totalUsage = usage
                        }
                    }
                    if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
                        responseToolCalls = toolCalls
                    }
                }
            }

            // Add assistant message
            messages.append(.assistant(
                responseContent,
                toolCalls: responseToolCalls.isEmpty ? nil : responseToolCalls
            ))

            continuation.yield(.turnCompleted(turn: turnCount))

            // Handle tool calls
            if !responseToolCalls.isEmpty {
                for toolCall in responseToolCalls {
                    toolCallCount += 1
                    continuation.yield(.toolCallStarted(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    ))

                    // Check if this is a handoff
                    if let handoff = currentAgent.handoffs.first(where: { $0.name == toolCall.name }) {
                        // Parse handoff reason
                        let args = try? JSONDecoder().decode(
                            HandoffArguments.self,
                            from: Data(toolCall.arguments.utf8)
                        )
                        let reason = args?.reason ?? "Handoff requested"

                        // Check for cycles
                        if agentHistory.contains(handoff.targetAgent.name) {
                            throw AgentError.cyclicHandoff(agents: agentHistory + [handoff.targetAgent.name])
                        }

                        continuation.yield(.handoff(
                            from: currentAgent.name,
                            to: handoff.targetAgent.name,
                            reason: reason
                        ))

                        // Add tool result message
                        messages.append(.tool(
                            callId: toolCall.id,
                            content: "Handed off to \(handoff.targetAgent.name)"
                        ))

                        // Switch to new agent
                        currentAgent = handoff.targetAgent
                        agentHistory.append(currentAgent.name)

                        // Update system message for new agent
                        messages[0] = .system(currentAgent.instructions)

                        continuation.yield(.agentStarted(name: currentAgent.name))
                        continue
                    }

                    // Execute tool
                    guard let tool = currentAgent.tools.first(where: { $0.name == toolCall.name }) else {
                        let error = "Tool not found: \(toolCall.name)"
                        messages.append(.tool(callId: toolCall.id, content: "Error: \(error)"))
                        continuation.yield(.toolCallCompleted(
                            name: toolCall.name,
                            result: error,
                            isError: true
                        ))
                        continue
                    }

                    do {
                        let result = try await tool.execute(arguments: toolCall.arguments, context: context)
                        messages.append(.tool(callId: toolCall.id, content: result))
                        continuation.yield(.toolCallCompleted(
                            name: toolCall.name,
                            result: result,
                            isError: false
                        ))
                    } catch {
                        let errorMessage = "Tool execution failed: \(error.localizedDescription)"
                        messages.append(.tool(callId: toolCall.id, content: "Error: \(errorMessage)"))
                        continuation.yield(.toolCallCompleted(
                            name: toolCall.name,
                            result: errorMessage,
                            isError: true
                        ))
                    }
                }

                // Continue loop to process tool results
                continue
            }

            // No tool calls - this is the final response
            var finalOutput = responseContent

            // Validate output with guardrails
            for guardrail in currentAgent.outputGuardrails {
                let result = try await guardrail.validate(finalOutput, context: context)
                continuation.yield(.guardrailTriggered(name: guardrail.name, result: result))

                switch result {
                case .passed:
                    continue
                case .modified(let newContent, _):
                    finalOutput = newContent
                case .blocked(let reason):
                    throw AgentError.outputBlocked(guardrail: guardrail.name, reason: reason)
                }
            }

            // Complete successfully
            let runResult = RunResult(
                output: finalOutput,
                messages: messages,
                finalAgent: currentAgent.name,
                toolCallCount: toolCallCount,
                turnCount: turnCount,
                tokenUsage: totalUsage
            )

            continuation.yield(.completed(runResult))
            continuation.finish()
            return
        }

        // Max turns exceeded
        throw AgentError.maxTurnsExceeded(turns: maxTurns)
    }

    // MARK: - Task Management

    private func trackTask(_ id: UUID, task: Task<Void, Never>) {
        activeTasks[id] = task
    }

    private func removeTask(_ id: UUID) {
        activeTasks.removeValue(forKey: id)
    }

    /// Cancel all active agent executions
    public func cancelAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }
}
