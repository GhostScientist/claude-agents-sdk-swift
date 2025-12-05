import Foundation

// MARK: - Tool Protocol

/// A capability that agents can invoke to perform actions beyond text generation.
///
/// Tools extend an agent's abilities, allowing it to perform calculations, fetch data,
/// interact with external services, or execute arbitrary code. The LLM decides when
/// to call tools based on the user's request and the tool's description.
///
/// ## Overview
///
/// When an agent has tools available, the LLM can:
/// 1. Analyze the user's request
/// 2. Decide which tool(s) to call
/// 3. Generate the appropriate arguments
/// 4. Receive the tool's result
/// 5. Use that result to formulate its response
///
/// ## Creating Tools
///
/// There are several ways to create tools:
///
/// ### Using FunctionTool (Recommended for Simple Cases)
///
/// ```swift
/// let weatherTool = FunctionTool(
///     name: "get_weather",
///     description: "Get the current weather for a location",
///     inputSchema: .object(
///         properties: [
///             "city": .string("The city name"),
///             "units": .string("Temperature units: celsius or fahrenheit")
///         ],
///         required: ["city"]
///     )
/// ) { arguments, context in
///     let args = try JSONDecoder().decode(WeatherArgs.self, from: Data(arguments.utf8))
///     return "The weather in \(args.city) is 72°F and sunny."
/// }
/// ```
///
/// ### Conforming to Tool Protocol
///
/// For complex tools with state or dependencies:
///
/// ```swift
/// struct DatabaseSearchTool: Tool {
///     let name = "search_database"
///     let description = "Search the product database"
///
///     let database: ProductDatabase
///
///     var inputSchema: JSONSchema {
///         .object(
///             properties: ["query": .string("Search query")],
///             required: ["query"]
///         )
///     }
///
///     func execute(arguments: String, context: any AgentContext) async throws -> String {
///         let args = try JSONDecoder().decode(SearchArgs.self, from: Data(arguments.utf8))
///         let results = try await database.search(args.query)
///         return results.map { $0.description }.joined(separator: "\n")
///     }
/// }
/// ```
///
/// ## Best Practices
///
/// - **Clear descriptions**: Write descriptions that help the LLM understand when to use the tool
/// - **Specific schemas**: Define precise input schemas to reduce LLM errors
/// - **Helpful errors**: Return informative error messages that help the LLM recover
/// - **Idempotent when possible**: Tools may be called multiple times with the same arguments
///
/// ## Topics
///
/// ### Required Properties
/// - ``name``
/// - ``description``
/// - ``inputSchema``
///
/// ### Execution
/// - ``execute(arguments:context:)``
public protocol Tool: Sendable {
    /// The unique name of the tool (used by the LLM to invoke it)
    var name: String { get }

    /// Human-readable description of what the tool does
    var description: String { get }

    /// JSON Schema describing the input parameters
    var inputSchema: JSONSchema { get }

    /// Execute the tool with the given arguments
    /// - Parameters:
    ///   - arguments: JSON string containing the tool arguments
    ///   - context: The current agent context
    /// - Returns: String result of the tool execution
    func execute(arguments: String, context: any AgentContext) async throws -> String
}

// MARK: - AnyTool

/// A type-erased wrapper for any tool.
///
/// `AnyTool` allows you to work with tools of different types in a uniform way.
/// This is useful for collections of heterogeneous tools or when the specific
/// tool type doesn't matter.
///
/// ## Example
///
/// ```swift
/// let tools: [AnyTool] = [
///     AnyTool(weatherTool),
///     AnyTool(calculatorTool),
///     AnyTool(searchTool)
/// ]
///
/// for tool in tools {
///     print("Tool: \(tool.name) - \(tool.description)")
/// }
/// ```
public struct AnyTool: Tool, @unchecked Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    private let _execute: @Sendable (String, any AgentContext) async throws -> String

    public init<T: Tool>(_ tool: T) {
        self.name = tool.name
        self.description = tool.description
        self.inputSchema = tool.inputSchema
        self._execute = tool.execute
    }

    public func execute(arguments: String, context: any AgentContext) async throws -> String {
        try await _execute(arguments, context)
    }
}

// MARK: - FunctionTool

/// A tool implementation that wraps a closure.
///
/// `FunctionTool` is the simplest way to create a tool. It takes a closure
/// that will be called when the LLM invokes the tool.
///
/// ## Basic Usage
///
/// ```swift
/// let calculator = FunctionTool(
///     name: "calculate",
///     description: "Perform a mathematical calculation",
///     inputSchema: .object(
///         properties: [
///             "expression": .string("The math expression to evaluate")
///         ],
///         required: ["expression"]
///     )
/// ) { arguments, context in
///     // Parse arguments and perform calculation
///     let args = try JSONDecoder().decode(CalcArgs.self, from: Data(arguments.utf8))
///     let result = try evaluate(args.expression)
///     return "Result: \(result)"
/// }
/// ```
///
/// ## With Typed Arguments
///
/// Define a Codable struct for type-safe argument handling:
///
/// ```swift
/// struct SearchArgs: Codable {
///     let query: String
///     let limit: Int?
/// }
///
/// let search = FunctionTool(
///     name: "search",
///     description: "Search for items",
///     inputSchema: .object(
///         properties: [
///             "query": .string("Search query"),
///             "limit": .integer("Maximum results to return")
///         ],
///         required: ["query"]
///     )
/// ) { arguments, context in
///     let args = try JSONDecoder().decode(SearchArgs.self, from: Data(arguments.utf8))
///     let results = performSearch(args.query, limit: args.limit ?? 10)
///     return results.joined(separator: "\n")
/// }
/// ```
public struct FunctionTool: Tool {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    private let handler: @Sendable (String, any AgentContext) async throws -> String

    public init(
        name: String,
        description: String,
        inputSchema: JSONSchema,
        handler: @escaping @Sendable (String, any AgentContext) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }

    public func execute(arguments: String, context: any AgentContext) async throws -> String {
        try await handler(arguments, context)
    }
}

// MARK: - ToolDefinition

/// The serialized representation of a tool sent to the LLM.
///
/// `ToolDefinition` is the wire format used to describe tools to the LLM.
/// It contains the tool's name, description, and JSON Schema for its parameters.
/// The ``Runner`` automatically converts ``Tool`` instances to `ToolDefinition`
/// when making LLM requests.
///
/// You typically don't need to create `ToolDefinition` directly unless you're
/// implementing a custom ``LLMProvider``.
public struct ToolDefinition: Sendable, Codable, Hashable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public init(from tool: any Tool) {
        self.name = tool.name
        self.description = tool.description
        self.inputSchema = tool.inputSchema
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: - Result Builder for Tools

/// A result builder for declaratively constructing tool arrays.
///
/// `ToolsBuilder` enables a SwiftUI-like syntax for defining agent tools:
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "Help users."
/// ) {
///     WeatherTool()
///     CalculatorTool()
///     if includeAdvanced {
///         AdvancedSearchTool()
///     }
/// }
/// ```
@resultBuilder
public struct ToolsBuilder {
    public static func buildBlock(_ tools: any Tool...) -> [any Tool] {
        tools
    }

    public static func buildOptional(_ tool: (any Tool)?) -> [any Tool] {
        tool.map { [$0] } ?? []
    }

    public static func buildEither(first tool: any Tool) -> [any Tool] {
        [tool]
    }

    public static func buildEither(second tool: any Tool) -> [any Tool] {
        [tool]
    }

    public static func buildArray(_ tools: [[any Tool]]) -> [any Tool] {
        tools.flatMap { $0 }
    }

    public static func buildExpression(_ tool: any Tool) -> [any Tool] {
        [tool]
    }

    public static func buildExpression(_ tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildBlock(_ tools: [any Tool]...) -> [any Tool] {
        tools.flatMap { $0 }
    }
}
