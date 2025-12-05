import Foundation

// MARK: - RunResult

/// The final outcome of running an agent, including output and execution metadata.
///
/// `RunResult` is returned by ``Runner/run(_:input:context:)`` and contains
/// everything you need to know about how the agent processed the request.
///
/// ## Basic Usage
///
/// ```swift
/// let result = try await runner.run(agent, input: "What's 2 + 2?")
///
/// print("Answer: \(result.output)")
/// print("Agent: \(result.finalAgent)")
/// print("Turns: \(result.turnCount)")
/// print("Tool calls: \(result.toolCallCount)")
///
/// if let usage = result.tokenUsage {
///     print("Tokens: \(usage.totalTokens)")
/// }
/// ```
///
/// ## Accessing Conversation History
///
/// The `messages` array contains the full conversation, useful for debugging
/// or continuing conversations:
///
/// ```swift
/// for message in result.messages {
///     print("\(message.role): \(message.content)")
/// }
/// ```
public struct RunResult: Sendable {
    /// The final output from the agent
    public let output: String

    /// All messages in the conversation
    public let messages: [Message]

    /// Name of the agent that produced the final output
    public let finalAgent: String

    /// Number of tool calls made
    public let toolCallCount: Int

    /// Number of turns (LLM calls) made
    public let turnCount: Int

    /// Total token usage
    public let tokenUsage: TokenUsage?

    public init(
        output: String,
        messages: [Message],
        finalAgent: String,
        toolCallCount: Int,
        turnCount: Int,
        tokenUsage: TokenUsage? = nil
    ) {
        self.output = output
        self.messages = messages
        self.finalAgent = finalAgent
        self.toolCallCount = toolCallCount
        self.turnCount = turnCount
        self.tokenUsage = tokenUsage
    }
}

// MARK: - AgentEvent

/// Events emitted during agent execution for real-time monitoring.
///
/// Subscribe to these events using ``Runner/stream(_:input:context:)`` to
/// build responsive UIs that show the agent's progress:
///
/// ```swift
/// for try await event in runner.stream(agent, input: "Hello") {
///     switch event {
///     case .agentStarted(let name):
///         showTypingIndicator(for: name)
///     case .textDelta(let text):
///         appendToResponse(text)
///     case .toolCallStarted(let name, _):
///         showToolUsage(name)
///     case .completed(let result):
///         hideTypingIndicator()
///         displayFinalResponse(result.output)
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Event Order
///
/// Events are emitted in this general order:
/// 1. ``agentStarted(name:)`` - Agent begins processing
/// 2. ``textDelta(_:)`` - Text tokens as they're generated
/// 3. ``toolCallStarted(name:arguments:)`` - Tool invocation begins
/// 4. ``toolCallCompleted(name:result:isError:)`` - Tool returns
/// 5. ``turnCompleted(turn:)`` - One LLM call cycle finished
/// 6. ``handoff(from:to:reason:)`` - If switching agents
/// 7. ``completed(_:)`` - Final result available
public enum AgentEvent: Sendable {
    /// Agent started processing
    case agentStarted(name: String)

    /// Text delta from the LLM
    case textDelta(String)

    /// Tool call started
    case toolCallStarted(name: String, arguments: String)

    /// Tool call completed
    case toolCallCompleted(name: String, result: String, isError: Bool)

    /// Handoff to another agent
    case handoff(from: String, to: String, reason: String)

    /// Guardrail was triggered
    case guardrailTriggered(name: String, result: GuardrailResult)

    /// Turn completed (one LLM call cycle)
    case turnCompleted(turn: Int)

    /// Agent completed successfully
    case completed(RunResult)

    /// Error occurred
    case error(AgentError)
}
