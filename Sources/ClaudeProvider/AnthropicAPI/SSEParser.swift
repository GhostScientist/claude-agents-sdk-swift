import Foundation

/// Parser for Server-Sent Events from Anthropic's streaming API
struct SSEParser {
    private var currentEvent: String?
    private var currentData: String = ""

    mutating func parse(line: String) -> SSEEvent? {
        // Trim whitespace from line
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Empty line indicates end of event
        if trimmedLine.isEmpty {
            defer {
                currentEvent = nil
                currentData = ""
            }

            guard !currentData.isEmpty else { return nil }
            return parseEvent(type: currentEvent, data: currentData)
        }

        // Parse line
        if trimmedLine.hasPrefix("event:") {
            currentEvent = trimmedLine.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if trimmedLine.hasPrefix("data:") {
            let dataContent = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespaces)

            // Handle ping specially - it comes as data: {"type": "ping"}
            if dataContent.contains("\"type\"") && dataContent.contains("\"ping\"") {
                return .ping
            }

            // If we have data content, try to parse it immediately for certain event types
            // This handles cases where empty lines might be stripped
            if !dataContent.isEmpty {
                currentData = dataContent

                // Try to parse immediately if we have enough info
                if let event = currentEvent, let result = parseEvent(type: event, data: currentData) {
                    currentEvent = nil
                    currentData = ""
                    return result
                }

                // For message_stop which may not have preceding event line
                if dataContent.contains("\"message_stop\"") {
                    currentEvent = nil
                    currentData = ""
                    return .messageStop
                }
            }
        } else if trimmedLine.hasPrefix(":") {
            // Comment line, ignore
        }

        return nil
    }

    private func parseEvent(type: String?, data: String) -> SSEEvent? {
        guard let jsonData = data.data(using: .utf8) else { return nil }

        do {
            switch type {
            case "message_start":
                let payload = try JSONDecoder().decode(MessageStartPayload.self, from: jsonData)
                return .messageStart(payload.message)

            case "content_block_start":
                let payload = try JSONDecoder().decode(ContentBlockStartPayload.self, from: jsonData)
                return .contentBlockStart(index: payload.index, block: payload.contentBlock)

            case "content_block_delta":
                let payload = try JSONDecoder().decode(ContentBlockDeltaPayload.self, from: jsonData)
                return .contentBlockDelta(index: payload.index, delta: payload.delta)

            case "content_block_stop":
                let payload = try JSONDecoder().decode(ContentBlockStopPayload.self, from: jsonData)
                return .contentBlockStop(index: payload.index)

            case "message_delta":
                let payload = try JSONDecoder().decode(MessageDeltaPayload.self, from: jsonData)
                return .messageDelta(payload.delta, usage: payload.usage)

            case "message_stop":
                return .messageStop

            case "ping":
                return .ping

            case "error":
                let payload = try JSONDecoder().decode(ErrorPayload.self, from: jsonData)
                return .error(payload.error)

            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

// MARK: - SSE Event Types

enum SSEEvent {
    case messageStart(StreamMessage)
    case contentBlockStart(index: Int, block: StreamContentBlock)
    case contentBlockDelta(index: Int, delta: StreamDelta)
    case contentBlockStop(index: Int)
    case messageDelta(StreamMessageDelta, usage: StreamUsage?)
    case messageStop
    case ping
    case error(StreamError)
}

// MARK: - Payload Types

struct MessageStartPayload: Decodable {
    let message: StreamMessage
}

struct StreamMessage: Decodable {
    let id: String
    let type: String
    let role: String
    let model: String
    let usage: StreamUsage?
}

struct StreamUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct ContentBlockStartPayload: Decodable {
    let index: Int
    let contentBlock: StreamContentBlock

    enum CodingKeys: String, CodingKey {
        case index
        case contentBlock = "content_block"
    }
}

enum StreamContentBlock: Decodable {
    case text(String)
    case toolUse(id: String, name: String)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            self = .toolUse(id: id, name: name)
        default:
            self = .text("")
        }
    }
}

struct ContentBlockDeltaPayload: Decodable {
    let index: Int
    let delta: StreamDelta
}

enum StreamDelta: Decodable {
    case textDelta(String)
    case inputJsonDelta(String)

    enum CodingKeys: String, CodingKey {
        case type, text
        case partialJson = "partial_json"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text_delta":
            let text = try container.decode(String.self, forKey: .text)
            self = .textDelta(text)
        case "input_json_delta":
            let json = try container.decode(String.self, forKey: .partialJson)
            self = .inputJsonDelta(json)
        default:
            self = .textDelta("")
        }
    }
}

struct ContentBlockStopPayload: Decodable {
    let index: Int
}

struct MessageDeltaPayload: Decodable {
    let delta: StreamMessageDelta
    let usage: StreamUsage?
}

struct StreamMessageDelta: Decodable {
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
    }
}

struct ErrorPayload: Decodable {
    let error: StreamError
}

struct StreamError: Decodable {
    let type: String
    let message: String
}
