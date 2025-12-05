import Foundation

/// Represents a role in a conversation
public enum MessageRole: String, Codable, Sendable, Hashable {
    case system
    case user
    case assistant
    case tool
}

/// Represents a single message in an agent conversation
public struct Message: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let role: MessageRole
    public let content: String
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.timestamp = timestamp
    }

    // Convenience initializers
    public static func system(_ content: String) -> Message {
        Message(role: .system, content: content)
    }

    public static func user(_ content: String) -> Message {
        Message(role: .user, content: content)
    }

    public static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: .assistant, content: content, toolCalls: toolCalls)
    }

    public static func tool(callId: String, content: String) -> Message {
        Message(role: .tool, content: content, toolCallId: callId)
    }
}

/// Content block types for multimodal messages (future expansion)
public enum ContentBlock: Sendable, Codable, Hashable {
    case text(String)
    case image(ImageContent)
    case toolUse(ToolCall)
    case toolResult(ToolResult)

    public struct ImageContent: Sendable, Codable, Hashable {
        public let mediaType: String
        public let data: Data

        public init(mediaType: String, data: Data) {
            self.mediaType = mediaType
            self.data = data
        }
    }
}
