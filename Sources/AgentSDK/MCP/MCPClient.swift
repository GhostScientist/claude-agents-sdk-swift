//
//  MCPClient.swift
//  AgentSDK
//
//  MCP Client implementation supporting stdio and SSE transports
//

import Foundation

#if os(macOS)
import Darwin
#endif

// MARK: - MCP Transport Protocol

/// Protocol for MCP transport implementations.
///
/// Transports handle the low-level communication with MCP servers.
/// The SDK provides three built-in transports:
/// - ``StdioTransport``: For local process communication (macOS only)
/// - ``SSETransport``: For Server-Sent Events connections
/// - ``StreamableHTTPTransport``: For modern HTTP-based MCP servers
public protocol MCPTransport: Sendable {
    /// Sends a JSON-RPC request and waits for the response.
    func send(_ message: JSONRPCRequest) async throws -> JSONRPCResponse

    /// Sends a JSON-RPC notification (no response expected).
    func sendNotification(_ notification: JSONRPCNotification) async throws

    /// Closes the transport connection.
    func close() async
}

// MARK: - MCP Client

/// A client for communicating with MCP (Model Context Protocol) servers.
///
/// `MCPClient` handles the MCP protocol lifecycle including initialization,
/// tool discovery, and tool invocation. It supports multiple transport types
/// for different deployment scenarios.
///
/// ## Supported Transports
///
/// - **Stdio**: For local MCP servers running as child processes (macOS only)
/// - **SSE**: For servers using Server-Sent Events
/// - **Streamable HTTP**: For modern MCP servers like HuggingFace
///
/// ## Example
///
/// ```swift
/// // Connect to HuggingFace MCP server
/// let serverInfo = MCPClient.MCPServerInfo(
///     name: "HuggingFace",
///     url: URL(string: "https://huggingface.co/mcp")!,
///     headers: ["Authorization": "Bearer \(token)"],
///     useStreamableHTTP: true
/// )
///
/// let client = try await MCPClient(serverInfo: serverInfo)
/// let result = try await client.initialize()
/// let tools = try await client.listTools()
/// ```
public actor MCPClient {
    public let serverInfo: MCPServerInfo
    private let transport: MCPTransport
    private var serverCapabilities: MCPServerCapabilities?
    private var isInitialized = false
    private var requestId = 0

    public struct MCPServerInfo: Sendable {
        public let name: String
        public let command: String?
        public let args: [String]?
        public let url: URL?
        public let headers: [String: String]
        public let transport: TransportType

        public enum TransportType: Sendable {
            case stdio
            case sse
            case streamableHTTP  // Newer MCP transport (used by HuggingFace)
        }

        public init(name: String, command: String, args: [String] = []) {
            self.name = name
            self.command = command
            self.args = args
            self.url = nil
            self.headers = [:]
            self.transport = .stdio
        }

        public init(name: String, url: URL, headers: [String: String] = [:], useStreamableHTTP: Bool = false) {
            self.name = name
            self.command = nil
            self.args = nil
            self.url = url
            self.headers = headers
            self.transport = useStreamableHTTP ? .streamableHTTP : .sse
        }
    }

    public init(serverInfo: MCPServerInfo) async throws {
        self.serverInfo = serverInfo

        switch serverInfo.transport {
        case .stdio:
            #if os(macOS)
            guard let command = serverInfo.command else {
                throw MCPError.invalidConfiguration("stdio transport requires command")
            }
            self.transport = try await StdioTransport(command: command, args: serverInfo.args ?? [])
            #else
            throw MCPError.invalidConfiguration("stdio transport is only available on macOS. Use SSE transport on iOS.")
            #endif

        case .sse:
            guard let url = serverInfo.url else {
                throw MCPError.invalidConfiguration("SSE transport requires URL")
            }
            self.transport = try await SSETransport(url: url, headers: serverInfo.headers)

        case .streamableHTTP:
            guard let url = serverInfo.url else {
                throw MCPError.invalidConfiguration("Streamable HTTP transport requires URL")
            }
            self.transport = StreamableHTTPTransport(url: url, headers: serverInfo.headers)
        }
    }

    private func nextRequestId() -> String {
        requestId += 1
        return "\(requestId)"
    }

    // MARK: - Lifecycle

    public func initialize() async throws -> MCPInitializeResult {
        let params = MCPInitializeParams(
            clientInfo: MCPImplementation(name: "AgentSDK", version: "1.0.0")
        )

        let paramsValue = try encodeToValue(params)
        guard case .object(let paramsDict) = paramsValue else {
            throw MCPError.encodingError("Failed to encode params")
        }

        let request = JSONRPCRequest(
            id: nextRequestId(),
            method: "initialize",
            params: paramsDict
        )

        let response = try await transport.send(request)

        if let error = response.error {
            throw MCPError.serverError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw MCPError.invalidResponse("No result in initialize response")
        }

        let initResult: MCPInitializeResult = try decodeFromValue(result)
        self.serverCapabilities = initResult.capabilities
        self.isInitialized = true

        // Send initialized notification
        let notification = JSONRPCNotification(method: "notifications/initialized")
        try await transport.sendNotification(notification)

        return initResult
    }

    public func close() async {
        await transport.close()
    }

    // MARK: - Tools

    public func listTools() async throws -> [MCPTool] {
        guard isInitialized else {
            throw MCPError.notInitialized
        }

        let request = JSONRPCRequest(
            id: nextRequestId(),
            method: "tools/list",
            params: nil
        )

        let response = try await transport.send(request)

        if let error = response.error {
            throw MCPError.serverError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw MCPError.invalidResponse("No result in tools/list response")
        }

        let listResult: MCPListToolsResult = try decodeFromValue(result)
        return listResult.tools
    }

    public func callTool(name: String, arguments: [String: Any]?) async throws -> MCPCallToolResult {
        guard isInitialized else {
            throw MCPError.notInitialized
        }

        var params: [String: AnyCodableValue] = ["name": .string(name)]
        if let arguments = arguments {
            params["arguments"] = .object(arguments.mapValues { AnyCodableValue.from($0) })
        }

        let request = JSONRPCRequest(
            id: nextRequestId(),
            method: "tools/call",
            params: params
        )

        let response = try await transport.send(request)

        if let error = response.error {
            throw MCPError.serverError(code: error.code, message: error.message)
        }

        guard let result = response.result else {
            throw MCPError.invalidResponse("No result in tools/call response")
        }

        return try decodeFromValue(result)
    }

    // MARK: - Helpers

    private func encodeToValue<T: Encodable>(_ value: T) throws -> AnyCodableValue {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(AnyCodableValue.self, from: data)
    }

    private func decodeFromValue<T: Decodable>(_ value: AnyCodableValue) throws -> T {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - MCP Errors

public enum MCPError: Error, LocalizedError {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case notInitialized
    case serverError(code: Int, message: String)
    case invalidResponse(String)
    case encodingError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg): return "Invalid configuration: \(msg)"
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .notInitialized: return "MCP client not initialized"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .encodingError(let msg): return "Encoding error: \(msg)"
        case .timeout: return "Request timed out"
        }
    }
}

// MARK: - Stdio Transport (macOS only)

#if os(macOS)
actor StdioTransport: MCPTransport {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private var pendingRequests: [String: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var readTask: Task<Void, Never>?

    init(command: String, args: [String]) async throws {
        process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading

        do {
            try process.run()
        } catch {
            throw MCPError.connectionFailed("Failed to start process: \(error)")
        }

        // Start reading responses
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    private func readLoop() async {
        var buffer = Data()

        while !Task.isCancelled {
            do {
                let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    DispatchQueue.global().async { [stdout] in
                        let available = stdout.availableData
                        if available.isEmpty {
                            continuation.resume(returning: Data())
                        } else {
                            continuation.resume(returning: available)
                        }
                    }
                }

                if data.isEmpty {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    continue
                }

                buffer.append(data)

                // Try to parse complete JSON-RPC messages (newline-delimited)
                while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let messageData = buffer[..<newlineIndex]
                    buffer = Data(buffer[(newlineIndex + 1)...])

                    if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: messageData) {
                        if let continuation = pendingRequests.removeValue(forKey: response.id) {
                            continuation.resume(returning: response)
                        }
                    }
                }
            } catch {
                break
            }
        }
    }

    func send(_ message: JSONRPCRequest) async throws -> JSONRPCResponse {
        let data = try JSONEncoder().encode(message)
        var messageData = data
        messageData.append(UInt8(ascii: "\n"))

        stdin.write(messageData)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[message.id] = continuation
        }
    }

    func sendNotification(_ notification: JSONRPCNotification) async throws {
        let data = try JSONEncoder().encode(notification)
        var messageData = data
        messageData.append(UInt8(ascii: "\n"))
        stdin.write(messageData)
    }

    func close() async {
        readTask?.cancel()
        process.terminate()
    }
}
#endif

// MARK: - SSE Transport

actor SSETransport: MCPTransport {
    private let baseURL: URL
    private let session: URLSession
    private var messageEndpoint: URL?
    private var headers: [String: String]
    private var sseTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<JSONRPCResponse, Error>] = [:]

    init(url: URL, headers: [String: String] = [:]) async throws {
        self.baseURL = url
        self.headers = headers

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        // Connect to SSE endpoint to get the message endpoint
        try await connectSSE()
    }

    private func connectSSE() async throws {
        // Determine the SSE endpoint URL
        // If the URL doesn't end with /sse, append it (common MCP pattern)
        var sseURL = baseURL
        if !baseURL.path.hasSuffix("/sse") && !baseURL.path.hasSuffix("/sse/") {
            sseURL = baseURL.appendingPathComponent("sse")
        }

        var request = URLRequest(url: sseURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        AgentLogger.debug("SSE connecting to \(sseURL)", subsystem: "mcp")
        AgentLogger.debug("SSE headers: \(headers.keys.joined(separator: ", "))", subsystem: "mcp")

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.connectionFailed("Not an HTTP response")
        }

        AgentLogger.debug("SSE HTTP status: \(httpResponse.statusCode)", subsystem: "mcp")

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Start reading SSE events in background
        sseTask = Task {
            do {
                for try await line in bytes.lines {
                    AgentLogger.debug("SSE line: \(line.prefix(100))", subsystem: "mcp")
                    await handleSSELine(line)
                }
            } catch {
                AgentLogger.error("Error reading SSE: \(error)", subsystem: "mcp")
            }
        }

        // Wait a moment for the endpoint event
        try await Task.sleep(nanoseconds: 500_000_000)

        // If no message endpoint was received, use default
        if messageEndpoint == nil {
            // The message endpoint should be at /message relative to base URL
            messageEndpoint = baseURL.appendingPathComponent("message")
            AgentLogger.debug("Using default message endpoint: \(messageEndpoint?.absoluteString ?? "nil")", subsystem: "mcp")
        }
    }

    private func handleSSELine(_ line: String) async {
        // Parse SSE format: "event: xxx" or "data: xxx"
        if line.hasPrefix("event:") {
            // Event type - we mainly care about "endpoint" and "message"
            return
        }

        if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)

            // Check if it's an endpoint announcement
            if data.hasPrefix("http") || data.hasPrefix("/") {
                if let url = URL(string: data, relativeTo: baseURL) {
                    messageEndpoint = url.absoluteURL
                    AgentLogger.debug("Got message endpoint: \(messageEndpoint?.absoluteString ?? "nil")", subsystem: "mcp")
                }
                return
            }

            // Try to parse as JSON-RPC response
            if let jsonData = data.data(using: .utf8),
               let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: jsonData) {
                if let continuation = pendingRequests.removeValue(forKey: response.id) {
                    continuation.resume(returning: response)
                }
            }
        }
    }

    func send(_ message: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let endpoint = messageEndpoint else {
            throw MCPError.connectionFailed("No message endpoint available")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(message)

        AgentLogger.debug("SSE sending to \(endpoint): \(message.method)", subsystem: "mcp")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.connectionFailed("Not an HTTP response")
        }

        AgentLogger.debug("SSE response status: \(httpResponse.statusCode)", subsystem: "mcp")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            AgentLogger.error("SSE error body: \(body)", subsystem: "mcp")
            throw MCPError.connectionFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Some servers return empty response for SSE (response comes via SSE stream)
        if data.isEmpty {
            return try await withCheckedThrowingContinuation { continuation in
                pendingRequests[message.id] = continuation
            }
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }

    func sendNotification(_ notification: JSONRPCNotification) async throws {
        guard let endpoint = messageEndpoint else {
            throw MCPError.connectionFailed("No message endpoint available")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(notification)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPError.connectionFailed("HTTP error sending notification")
        }
    }

    func close() async {
        sseTask?.cancel()
        session.invalidateAndCancel()
    }
}

// MARK: - Streamable HTTP Transport

/// Streamable HTTP transport for MCP servers.
///
/// This transport implements the MCP Streamable HTTP protocol, used by modern
/// MCP servers like HuggingFace. It uses simple POST requests with session
/// management via the `Mcp-Session-Id` header.
///
/// ## Features
///
/// - Session ID management for stateful servers
/// - Automatic SSE response parsing for hybrid servers
/// - Support for both JSON and SSE accept headers
actor StreamableHTTPTransport: MCPTransport {
    private let url: URL
    private let session: URLSession
    private let headers: [String: String]
    private var sessionId: String?

    init(url: URL, headers: [String: String] = [:]) {
        self.url = url
        self.headers = headers

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        AgentLogger.debug("HTTP transport initialized with URL: \(url)", subsystem: "mcp")
    }

    func send(_ message: JSONRPCRequest) async throws -> JSONRPCResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // MCP Streamable HTTP requires accepting both JSON and SSE
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add session ID if we have one (required after initialize)
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(message)

        AgentLogger.debug("HTTP POST \(url): \(message.method)", subsystem: "mcp")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.connectionFailed("Not an HTTP response")
        }

        AgentLogger.debug("HTTP response status: \(httpResponse.statusCode)", subsystem: "mcp")

        // Capture session ID from response headers
        if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
            self.sessionId = newSessionId
            AgentLogger.debug("Got session ID: \(newSessionId.prefix(20))...", subsystem: "mcp")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw MCPError.connectionFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Some servers return SSE-formatted responses even for HTTP transport
        // Parse out the JSON from "data: {...}" format if present
        let jsonData = extractJSONFromSSE(data) ?? data

        return try JSONDecoder().decode(JSONRPCResponse.self, from: jsonData)
    }

    /// Extract JSON data from SSE-formatted response
    /// Handles responses like "event: message\ndata: {...}\n\n"
    private func extractJSONFromSSE(_ data: Data) -> Data? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }

        // Look for "data: " line containing JSON
        let lines = str.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data:") {
                let jsonPart = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if jsonPart.hasPrefix("{") {
                    AgentLogger.debug("Extracted JSON from SSE format", subsystem: "mcp")
                    return jsonPart.data(using: .utf8)
                }
            }
        }
        return nil
    }

    func sendNotification(_ notification: JSONRPCNotification) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        // Add session ID if we have one
        if let sessionId = sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(notification)

        AgentLogger.debug("HTTP POST notification: \(notification.method)", subsystem: "mcp")

        let (_, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            // Capture session ID from response headers
            if let newSessionId = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                self.sessionId = newSessionId
            }

            if !(200...299).contains(httpResponse.statusCode) {
                AgentLogger.warning("Notification may have failed with status \(httpResponse.statusCode)", subsystem: "mcp")
            }
        }
    }

    func close() async {
        session.invalidateAndCancel()
    }
}
