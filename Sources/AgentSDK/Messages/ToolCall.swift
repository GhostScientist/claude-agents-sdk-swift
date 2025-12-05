import Foundation

/// Represents a tool call made by the LLM
public struct ToolCall: Sendable, Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String // JSON string

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Decode arguments as a specific type
    public func decodeArguments<T: Decodable>(_ type: T.Type) throws -> T {
        guard let data = arguments.data(using: .utf8) else {
            throw ToolCallError.invalidArgumentsEncoding
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Represents the result of a tool execution
public struct ToolResult: Sendable, Codable, Hashable {
    public let callId: String
    public let name: String
    public let content: String
    public let isError: Bool

    public init(callId: String, name: String, content: String, isError: Bool = false) {
        self.callId = callId
        self.name = name
        self.content = content
        self.isError = isError
    }

    /// Create a successful result from an encodable value
    public static func success<T: Encodable>(
        callId: String,
        name: String,
        value: T
    ) throws -> ToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(value)
        let content = String(data: data, encoding: .utf8) ?? "{}"
        return ToolResult(callId: callId, name: name, content: content, isError: false)
    }

    /// Create a successful result from a string
    public static func success(callId: String, name: String, content: String) -> ToolResult {
        ToolResult(callId: callId, name: name, content: content, isError: false)
    }

    /// Create an error result
    public static func error(callId: String, name: String, message: String) -> ToolResult {
        ToolResult(callId: callId, name: name, content: message, isError: true)
    }
}

/// Errors that can occur during tool call processing
public enum ToolCallError: Error, Sendable {
    case invalidArgumentsEncoding
    case decodingFailed(String)
    case toolNotFound(String)
    case executionFailed(String, underlying: Error)
}
