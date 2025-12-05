import AppIntents
import AgentSDK

/// Base protocol for agent-powered App Intents
@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol AgentIntent: AppIntent {
    associatedtype AgentType: AgentProtocol

    /// The agent to run
    var agent: AgentType { get }

    /// The LLM provider to use
    var provider: any LLMProvider { get }

    /// Maximum turns for the agent
    var maxTurns: Int { get }
}

extension AgentIntent {
    public var maxTurns: Int { 10 }
}

/// A simple intent that runs an agent with a text prompt
@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct RunAgentIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run AI Agent"
    public static var description = IntentDescription("Run an AI agent with a prompt")

    @Parameter(title: "Prompt", description: "What do you want the agent to do?")
    public var prompt: String

    // These would be configured by the app
    @MainActor
    private var agentProvider: (@Sendable @MainActor () -> (any AgentProtocol, any LLMProvider))?

    public init() {}

    @MainActor
    public init(
        prompt: String,
        agentProvider: @escaping @Sendable @MainActor () -> (any AgentProtocol, any LLMProvider)
    ) {
        self.prompt = prompt
        self.agentProvider = agentProvider
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let provider = agentProvider else {
            throw AgentIntentError.notConfigured
        }

        let (agent, llmProvider) = provider()
        let runner = Runner(provider: llmProvider, maxTurns: 10)
        let anyAgent = AnyAgent(agent)

        let result = try await runner.run(anyAgent, input: prompt)
        return .result(value: result.output)
    }
}

/// Errors specific to agent intents
public enum AgentIntentError: Error, LocalizedError {
    case notConfigured
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Agent intent is not properly configured"
        case .executionFailed(let reason):
            return "Agent execution failed: \(reason)"
        }
    }
}

// MARK: - Shortcuts Provider

// Note: Apps should create their own AppShortcutsProvider conforming type
// since AppShortcutsProvider.appShortcuts cannot return an empty array.
// See the example usage documentation below for how to implement this.

// MARK: - Example Usage Documentation

/*
 Example: Creating an agent-powered App Intent

 ```swift
 import AppIntents
 import AgentSDK
 import AgentSDKApple
 import ClaudeProvider

 struct AskAssistantIntent: AppIntent {
     static var title: LocalizedStringResource = "Ask Assistant"
     static var description = IntentDescription("Ask your AI assistant a question")

     @Parameter(title: "Question")
     var question: String

     func perform() async throws -> some IntentResult & ReturnsValue<String> {
         let agent = Agent<EmptyContext>(
             name: "Assistant",
             instructions: "You are a helpful assistant."
         )

         let provider = ClaudeProvider(
             apiKey: Configuration.anthropicAPIKey
         )

         let runner = Runner(provider: provider)
         let result = try await runner.run(agent, input: question)

         return .result(value: result.output)
     }
 }

 // Expose as a Shortcut
 struct MyAppShortcuts: AppShortcutsProvider {
     static var appShortcuts: [AppShortcut] {
         AppShortcut(
             intent: AskAssistantIntent(),
             phrases: [
                 "Ask \(.applicationName) a question",
                 "Ask \(.applicationName) \(\.$question)"
             ],
             shortTitle: "Ask Assistant",
             systemImageName: "brain"
         )
     }
 }
 ```
*/
