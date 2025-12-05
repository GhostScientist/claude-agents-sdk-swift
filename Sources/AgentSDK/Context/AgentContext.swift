import Foundation

// MARK: - AgentContext

/// Protocol for providing dependencies and state to tools during agent execution.
///
/// `AgentContext` allows you to inject services, configuration, or state that
/// tools need to function. For simple agents, use ``EmptyContext``. For more
/// complex scenarios, implement your own context type.
///
/// ## Basic Usage with EmptyContext
///
/// Most agents don't need custom context:
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "Help users."
/// )
/// ```
///
/// ## Custom Context with Dependencies
///
/// For tools that need access to services:
///
/// ```swift
/// struct AppContext: AgentContext {
///     let database: DatabaseService
///     let apiClient: APIClient
///
///     init() {
///         // Default initialization for protocol conformance
///         self.database = DatabaseService()
///         self.apiClient = APIClient()
///     }
///
///     init(database: DatabaseService, apiClient: APIClient) {
///         self.database = database
///         self.apiClient = apiClient
///     }
/// }
///
/// // In your tool:
/// func execute(arguments: String, context: any AgentContext) async throws -> String {
///     guard let ctx = context as? AppContext else {
///         throw ToolError.invalidContext
///     }
///     let results = try await ctx.database.query(...)
///     return results.description
/// }
/// ```
public protocol AgentContext: Sendable {
    init()
}

// MARK: - EmptyContext

/// A context with no dependencies, suitable for simple agents.
///
/// Use `EmptyContext` when your tools don't need access to external services
/// or shared state. This is the default for most agents.
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Calculator",
///     instructions: "Help with math.",
///     tools: [CalculatorTool()]
/// )
/// ```
public struct EmptyContext: AgentContext {
    public init() {}
}

// MARK: - CustomContext

/// A generic context wrapper for injecting typed dependencies.
///
/// `CustomContext` provides a type-safe way to pass dependencies to your tools
/// without creating a custom context type:
///
/// ```swift
/// struct MyDependencies: Sendable {
///     let database: Database
///     let logger: Logger
/// }
///
/// let deps = MyDependencies(database: db, logger: log)
/// let context = CustomContext(dependencies: deps)
///
/// let result = try await runner.run(
///     agent,
///     input: "Query the database",
///     context: context
/// )
/// ```
public struct CustomContext<Dependencies: Sendable>: AgentContext {
    public let dependencies: Dependencies

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // Required for protocol conformance, but should not be used
    public init() {
        fatalError("CustomContext requires dependencies. Use init(dependencies:) instead.")
    }
}

/// Mutable state during agent execution
public actor AgentExecutionState {
    public private(set) var messages: [Message]
    public private(set) var currentAgent: String
    public private(set) var turnCount: Int
    public private(set) var toolCallCount: Int
    public private(set) var totalTokens: TokenUsage?

    public init(
        messages: [Message] = [],
        currentAgent: String = "",
        turnCount: Int = 0,
        toolCallCount: Int = 0
    ) {
        self.messages = messages
        self.currentAgent = currentAgent
        self.turnCount = turnCount
        self.toolCallCount = toolCallCount
    }

    public func appendMessage(_ message: Message) {
        messages.append(message)
    }

    public func appendMessages(_ newMessages: [Message]) {
        messages.append(contentsOf: newMessages)
    }

    public func setCurrentAgent(_ name: String) {
        currentAgent = name
    }

    public func incrementTurn() {
        turnCount += 1
    }

    public func incrementToolCalls(by count: Int = 1) {
        toolCallCount += count
    }

    public func updateTokenUsage(_ usage: TokenUsage) {
        if let existing = totalTokens {
            totalTokens = TokenUsage(
                inputTokens: existing.inputTokens + usage.inputTokens,
                outputTokens: existing.outputTokens + usage.outputTokens
            )
        } else {
            totalTokens = usage
        }
    }
}
