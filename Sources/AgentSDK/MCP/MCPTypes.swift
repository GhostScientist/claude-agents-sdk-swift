//
//  MCPTypes.swift
//  AgentSDK
//
//  Model Context Protocol types based on the MCP specification
//

import Foundation

// MARK: - JSON-RPC Base Types

public let MCP_JSONRPC_VERSION = "2.0"
public let MCP_PROTOCOL_VERSION = "2024-11-05"

public typealias RequestId = String

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestId
    public let method: String
    public let params: [String: AnyCodableValue]?

    public init(id: RequestId, method: String, params: [String: AnyCodableValue]? = nil) {
        self.jsonrpc = MCP_JSONRPC_VERSION
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: RequestId
    public let result: AnyCodableValue?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: AnyCodableValue?
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: AnyCodableValue]?

    public init(method: String, params: [String: AnyCodableValue]? = nil) {
        self.jsonrpc = MCP_JSONRPC_VERSION
        self.method = method
        self.params = params
    }
}

// MARK: - MCP Initialize

public struct MCPClientCapabilities: Codable, Sendable {
    public let roots: RootsCapability?
    public let sampling: SamplingCapability?

    public init(roots: RootsCapability? = nil, sampling: SamplingCapability? = nil) {
        self.roots = roots
        self.sampling = sampling
    }

    public struct RootsCapability: Codable, Sendable {
        public let listChanged: Bool?
        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    public struct SamplingCapability: Codable, Sendable {
        public init() {}
    }
}

public struct MCPServerCapabilities: Codable, Sendable {
    public let tools: ToolsCapability?
    public let resources: ResourcesCapability?
    public let prompts: PromptsCapability?

    public struct ToolsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }

    public struct ResourcesCapability: Codable, Sendable {
        public let subscribe: Bool?
        public let listChanged: Bool?
    }

    public struct PromptsCapability: Codable, Sendable {
        public let listChanged: Bool?
    }
}

public struct MCPImplementation: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPInitializeParams: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: MCPClientCapabilities
    public let clientInfo: MCPImplementation

    public init(
        protocolVersion: String = MCP_PROTOCOL_VERSION,
        capabilities: MCPClientCapabilities = MCPClientCapabilities(),
        clientInfo: MCPImplementation
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

public struct MCPInitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: MCPServerCapabilities
    public let serverInfo: MCPImplementation
    public let instructions: String?
}

// MARK: - MCP Tools

public struct MCPTool: Codable, Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: MCPToolInputSchema

    public struct MCPToolInputSchema: Codable, Sendable {
        public let type: String
        public let properties: [String: AnyCodableValue]?
        public let required: [String]?

        enum CodingKeys: String, CodingKey {
            case type, properties, required
        }
    }
}

public struct MCPListToolsResult: Codable, Sendable {
    public let tools: [MCPTool]
    public let nextCursor: String?
}

public struct MCPCallToolParams: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodableValue]?

    public init(name: String, arguments: [String: AnyCodableValue]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

public struct MCPCallToolResult: Codable, Sendable {
    public let content: [MCPContent]
    public let isError: Bool?
}

public enum MCPContent: Codable, Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case resource(uri: String, mimeType: String?, text: String?)

    enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "resource":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            let text = try container.decodeIfPresent(String.self, forKey: .text)
            self = .resource(uri: uri, mimeType: mimeType, text: text)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let uri, let mimeType, let text):
            try container.encode("resource", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
            try container.encodeIfPresent(text, forKey: .text)
        }
    }

    public var textValue: String {
        switch self {
        case .text(let text): return text
        case .image: return "[Image]"
        case .resource(let uri, _, let text): return text ?? "[Resource: \(uri)]"
        }
    }
}

// MARK: - Type-erased Codable Value

public enum AnyCodableValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodableValue].self) {
            self = .object(object)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: AnyCodableValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public static func from(_ any: Any) -> AnyCodableValue {
        switch any {
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(value)
        case let value as Double:
            return .double(value)
        case let value as String:
            return .string(value)
        case let value as [Any]:
            return .array(value.map { from($0) })
        case let value as [String: Any]:
            return .object(value.mapValues { from($0) })
        default:
            return .null
        }
    }

    public func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toAny() }
        case .object(let v): return v.mapValues { $0.toAny() }
        }
    }
}
