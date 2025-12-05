import Foundation
import AgentSDK

// MARK: - Request Types

struct AnthropicMessagesRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double?
    let tools: [AnthropicTool]?
    var stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, tools, stream
        case maxTokens = "max_tokens"
    }
}

struct AnthropicMessage: Codable {
    let role: String
    let content: [AnthropicContentBlock]
}

enum AnthropicContentBlock: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])
    case toolResult(toolUseId: String, content: String)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: AnyCodable].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input.mapValues { $0.value })
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = try container.decode(String.self, forKey: .content)
            self = .toolResult(toolUseId: toolUseId, content: content)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            let encodableInput = input.mapValues { AnyCodable($0) }
            try container.encode(encodableInput, forKey: .input)
        case .toolResult(let toolUseId, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
        }
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

// MARK: - Response Types

struct AnthropicMessagesResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

struct AnthropicUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Error Types

struct AnthropicError: Decodable {
    let type: String
    let error: AnthropicErrorDetail
}

struct AnthropicErrorDetail: Decodable {
    let type: String
    let message: String
}
