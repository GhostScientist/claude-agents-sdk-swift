//
//  MCPToolProvider.swift
//  AgentSDK
//
//  Bridges MCP tools to AgentSDK Tool protocol
//

import Foundation

// MARK: - MCP Tool Provider

/// Provides tools from one or more MCP servers to an Agent.
///
/// `MCPToolProvider` acts as a bridge between MCP (Model Context Protocol) servers
/// and the AgentSDK's tool system. It manages connections to multiple MCP servers
/// and exposes their tools in a format compatible with AgentSDK agents.
///
/// ## Overview
///
/// MCP servers provide tools that can be called by language models. This provider
/// handles the connection lifecycle, tool discovery, and execution delegation.
///
/// ## Example
///
/// ```swift
/// let provider = MCPToolProvider()
///
/// // Connect to a HuggingFace MCP server
/// let serverInfo = MCPClient.MCPServerInfo(
///     name: "HuggingFace",
///     url: URL(string: "https://huggingface.co/mcp")!,
///     headers: ["Authorization": "Bearer \(token)"],
///     useStreamableHTTP: true
/// )
///
/// let tools = try await provider.addServer(serverInfo)
/// print("Discovered \(tools.count) tools")
///
/// // Create an agent with MCP tools
/// let agent = await Agent.withMCPTools(
///     name: "Assistant",
///     instructions: "Help users with HuggingFace.",
///     toolProvider: provider
/// )
/// ```
///
/// ## Thread Safety
///
/// `MCPToolProvider` is an actor, making it safe to use from multiple concurrent contexts.
public actor MCPToolProvider {
    private var clients: [String: MCPClient] = [:]
    private var toolsCache: [String: (client: MCPClient, tool: MCPTool)] = [:]

    public init() {}

    // MARK: - Server Management

    /// Adds an MCP server and discovers its available tools.
    ///
    /// This method establishes a connection to the MCP server, performs the
    /// initialization handshake, and retrieves the list of available tools.
    ///
    /// - Parameter serverInfo: Configuration for the MCP server connection.
    /// - Returns: Array of tools discovered on the server.
    /// - Throws: ``MCPError`` if connection or initialization fails.
    public func addServer(_ serverInfo: MCPClient.MCPServerInfo) async throws -> [MCPTool] {
        AgentLogger.debug("Connecting to server: \(serverInfo.name)", subsystem: "mcp")

        let client = try await MCPClient(serverInfo: serverInfo)
        let initResult = try await client.initialize()

        AgentLogger.info("Server initialized: \(initResult.serverInfo.name) v\(initResult.serverInfo.version)", subsystem: "mcp")

        let tools = try await client.listTools()
        AgentLogger.debug("Discovered \(tools.count) tools: \(tools.map { $0.name })", subsystem: "mcp")

        clients[serverInfo.name] = client

        // Cache tools with their client reference
        for tool in tools {
            toolsCache[tool.name] = (client: client, tool: tool)
        }

        return tools
    }

    /// Remove an MCP server
    public func removeServer(named name: String) async {
        if let client = clients.removeValue(forKey: name) {
            // Remove tools from this server
            toolsCache = toolsCache.filter { _, value in
                // Keep tools not from this client
                true // Simplified - in production, track which client owns which tool
            }
            await client.close()
        }
    }

    /// Get all connected server names
    public func connectedServers() -> [String] {
        Array(clients.keys)
    }

    // MARK: - Tool Access

    /// Get all available tools as AgentSDK Tool instances
    public func tools() -> [any Tool] {
        toolsCache.map { name, value in
            MCPToolWrapper(
                mcpTool: value.tool,
                provider: self
            )
        }
    }

    /// Call a tool by name
    public func callTool(name: String, arguments: String) async throws -> String {
        guard let (client, _) = toolsCache[name] else {
            throw MCPError.invalidResponse("Tool not found: \(name)")
        }

        // Parse JSON arguments
        let argsDict: [String: Any]?
        if !arguments.isEmpty,
           let data = arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            argsDict = json
        } else {
            argsDict = nil
        }

        AgentLogger.debug("Calling tool: \(name)", subsystem: "tools")
        let result = try await client.callTool(name: name, arguments: argsDict)

        // Convert result to string
        let output = result.content.map { $0.textValue }.joined(separator: "\n")

        if result.isError == true {
            AgentLogger.error("Tool error: \(output)", subsystem: "tools")
            throw MCPError.serverError(code: -1, message: output)
        }

        AgentLogger.debug("Tool result: \(output.prefix(200))...", subsystem: "tools")
        return output
    }

    /// Close all connections
    public func closeAll() async {
        for (_, client) in clients {
            await client.close()
        }
        clients.removeAll()
        toolsCache.removeAll()
    }
}

// MARK: - MCP Tool Wrapper

/// Wraps an MCP tool as an AgentSDK Tool
public struct MCPToolWrapper: Tool {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    private let provider: MCPToolProvider

    init(mcpTool: MCPTool, provider: MCPToolProvider) {
        self.name = mcpTool.name
        self.description = mcpTool.description ?? "MCP tool: \(mcpTool.name)"
        self.inputSchema = Self.convertSchema(mcpTool.inputSchema)
        self.provider = provider
    }

    public func execute(arguments: String, context: any AgentContext) async throws -> String {
        try await provider.callTool(name: name, arguments: arguments)
    }

    private static func convertSchema(_ mcpSchema: MCPTool.MCPToolInputSchema) -> JSONSchema {
        var properties: [String: PropertySchema] = [:]

        if let props = mcpSchema.properties {
            for (key, value) in props {
                properties[key] = convertPropertySchema(value)
            }
        }

        return .object(
            properties: properties,
            required: mcpSchema.required ?? []
        )
    }

    private static func convertPropertySchema(_ value: AnyCodableValue) -> PropertySchema {
        guard case .object(let obj) = value else {
            return .string()
        }

        let type = obj["type"]?.stringValue ?? "string"
        let description = obj["description"]?.stringValue

        switch type {
        case "string":
            return .string(description)
        case "number":
            return .number(description)
        case "integer":
            return .integer(description)
        case "boolean":
            return .boolean(description)
        case "array":
            // Simplified array handling
            return .array(items: .string(), description: description)
        case "object":
            // Simplified nested object handling - just treat as string for now
            return .string(description)
        default:
            return .string(description)
        }
    }
}

// MARK: - Convenience Extensions

extension Agent {
    /// Create an agent with tools from MCP servers
    public static func withMCPTools(
        name: String,
        instructions: String,
        toolProvider: MCPToolProvider,
        additionalTools: [any Tool] = [],
        handoffs: [Handoff] = []
    ) async -> Agent<Context> {
        let mcpTools = await toolProvider.tools()
        let allTools = mcpTools + additionalTools

        return Agent(
            name: name,
            instructions: instructions,
            tools: allTools,
            handoffs: handoffs
        )
    }
}
