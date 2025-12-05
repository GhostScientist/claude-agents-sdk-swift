import SwiftUI
import AgentSDK

/// Observable view model for managing agent state in SwiftUI
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable
@MainActor
public final class AgentViewModel<A: AgentProtocol> {
    // MARK: - Public State

    /// Whether the agent is currently running
    public private(set) var isRunning: Bool = false

    /// All messages in the conversation
    public private(set) var messages: [Message] = []

    /// Currently streaming text (updated as tokens arrive)
    public private(set) var streamingText: String = ""

    /// Name of the currently active agent (useful for multi-agent handoffs)
    public private(set) var currentAgentName: String = ""

    /// Recent tool calls for UI display
    public private(set) var recentToolCalls: [ToolCallInfo] = []

    /// Last error that occurred
    public private(set) var error: AgentError?

    /// Total tokens used in this session
    public private(set) var tokenUsage: TokenUsage?

    // MARK: - Private State

    private let agent: A
    private let runner: Runner
    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(agent: A, provider: any LLMProvider, maxTurns: Int = 10) {
        self.agent = agent
        self.runner = Runner(provider: provider, maxTurns: maxTurns)
        self.currentAgentName = agent.name
    }

    // MARK: - Public Methods

    /// Send a message to the agent and stream the response
    public func send(_ input: String) {
        // Cancel any existing task
        currentTask?.cancel()

        // Reset state
        isRunning = true
        streamingText = ""
        error = nil
        recentToolCalls = []

        // Add user message immediately
        messages.append(.user(input))

        currentTask = Task {
            do {
                for try await event in await runner.stream(agent, input: input) {
                    await handleEvent(event)
                }
            } catch is CancellationError {
                // Task was cancelled, ignore
            } catch {
                self.error = error as? AgentError ?? .unknown(error)
            }

            isRunning = false
        }
    }

    /// Cancel the current agent execution
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
    }

    /// Clear all messages and reset state
    public func clear() {
        cancel()
        messages = []
        streamingText = ""
        currentAgentName = agent.name
        recentToolCalls = []
        error = nil
        tokenUsage = nil
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: AgentEvent) async {
        switch event {
        case .agentStarted(let name):
            currentAgentName = name

        case .textDelta(let delta):
            streamingText += delta

        case .toolCallStarted(let name, let arguments):
            let info = ToolCallInfo(
                name: name,
                arguments: arguments,
                status: .running,
                result: nil
            )
            recentToolCalls.append(info)

        case .toolCallCompleted(let name, let result, let isError):
            if let index = recentToolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) {
                recentToolCalls[index] = ToolCallInfo(
                    name: name,
                    arguments: recentToolCalls[index].arguments,
                    status: isError ? .failed : .completed,
                    result: result
                )
            }

        case .handoff(_, let to, _):
            currentAgentName = to

        case .guardrailTriggered(let name, let result):
            switch result {
            case .blocked(let reason):
                error = .inputBlocked(guardrail: name, reason: reason)
            default:
                break
            }

        case .turnCompleted:
            // Finalize any streaming text as an assistant message
            if !streamingText.isEmpty {
                messages.append(.assistant(streamingText))
                streamingText = ""
            }

        case .completed(let result):
            // Add final message if not already added
            if !result.output.isEmpty && (messages.last?.content != result.output) {
                messages.append(.assistant(result.output))
            }
            tokenUsage = result.tokenUsage
            streamingText = ""

        case .error(let agentError):
            error = agentError
        }
    }
}

// MARK: - Supporting Types

/// Information about a tool call for UI display
public struct ToolCallInfo: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let arguments: String
    public let status: ToolCallStatus
    public let result: String?
}

public enum ToolCallStatus: Sendable {
    case running
    case completed
    case failed
}
