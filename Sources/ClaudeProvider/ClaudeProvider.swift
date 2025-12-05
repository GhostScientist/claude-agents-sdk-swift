import Foundation
import AgentSDK

/// LLM provider for Anthropic's Claude API.
///
/// `ClaudeProvider` implements the ``LLMProvider`` protocol, enabling agents
/// to use Claude models for reasoning and tool calling.
///
/// ## Quick Start
///
/// ```swift
/// let provider = ClaudeProvider(apiKey: "your-api-key")
///
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "You are a helpful assistant."
/// )
///
/// let runner = Runner(provider: provider)
/// let result = try await runner.run(agent, input: "Hello!")
/// ```
///
/// ## Model Selection
///
/// Use ``ClaudeModel`` to specify which Claude model to use:
///
/// ```swift
/// // Use Claude 4 Opus for complex tasks
/// let provider = ClaudeProvider(
///     apiKey: apiKey,
///     model: .claude45Opus
/// )
///
/// // Use Haiku for fast, simple tasks
/// let provider = ClaudeProvider(
///     apiKey: apiKey,
///     model: .claude45Haiku
/// )
/// ```
///
/// ## Streaming
///
/// The provider supports streaming responses for real-time UI updates:
///
/// ```swift
/// for try await event in provider.stream(request) {
///     switch event {
///     case .textDelta(let text):
///         print(text, terminator: "")
///     case .done(let response):
///         print("\nTotal tokens: \(response.usage?.totalTokens ?? 0)")
///     default:
///         break
///     }
/// }
/// ```
public struct ClaudeProvider: LLMProvider, Sendable {
    public let apiKey: String
    public let defaultModel: String
    public let baseURL: URL
    public let apiVersion: String

    private let session: URLSession

    public init(
        apiKey: String,
        model: ClaudeModel = .claude45Sonnet,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        apiVersion: String = "2023-06-01"
    ) {
        self.apiKey = apiKey
        self.defaultModel = model.rawValue
        self.baseURL = baseURL
        self.apiVersion = apiVersion

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    public func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let anthropicRequest = try buildAnthropicRequest(from: request)
        let (data, response) = try await performRequest(anthropicRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse("Not an HTTP response")
        }

        try validateResponse(httpResponse, data: data)

        let anthropicResponse = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        return convertToLLMResponse(anthropicResponse)
    }

    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var anthropicRequest = try buildAnthropicRequest(from: request)
                    anthropicRequest.stream = true

                    AgentLogger.debug("Making request to model: \(anthropicRequest.model)", subsystem: "provider")
                    AgentLogger.debug("Messages count: \(anthropicRequest.messages.count)", subsystem: "provider")

                    let urlRequest = try buildURLRequest(for: anthropicRequest, streaming: true)

                    let (bytes, response) = try await session.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AgentError.invalidResponse("Not an HTTP response")
                    }

                    AgentLogger.debug("HTTP status: \(httpResponse.statusCode)", subsystem: "provider")

                    if httpResponse.statusCode != 200 {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        AgentLogger.error("Error response: \(String(data: errorData, encoding: .utf8) ?? "nil")", subsystem: "provider")
                        try validateResponse(httpResponse, data: errorData)
                    }

                    var parser = SSEParser()
                    var accumulatedContent = ""
                    var accumulatedToolCalls: [String: ToolCallAccumulator] = [:]
                    var usage: TokenUsage?

                    AgentLogger.debug("Starting SSE stream", subsystem: "provider")

                    for try await line in bytes.lines {
                        guard let event = parser.parse(line: line) else { continue }

                        switch event {
                        case .contentBlockStart(let index, let block):
                            if case .toolUse(let id, let name) = block {
                                accumulatedToolCalls["\(index)"] = ToolCallAccumulator(id: id, name: name)
                                continuation.yield(.toolCallStart(id: id, name: name))
                            }

                        case .contentBlockDelta(let index, let delta):
                            switch delta {
                            case .textDelta(let text):
                                accumulatedContent += text
                                continuation.yield(.textDelta(text))
                            case .inputJsonDelta(let json):
                                if var accumulator = accumulatedToolCalls["\(index)"] {
                                    accumulator.arguments += json
                                    accumulatedToolCalls["\(index)"] = accumulator
                                    continuation.yield(.toolCallDelta(id: accumulator.id, argumentsDelta: json))
                                }
                            }

                        case .contentBlockStop(let index):
                            if let accumulator = accumulatedToolCalls["\(index)"] {
                                continuation.yield(.toolCallComplete(id: accumulator.id))
                            }

                        case .messageStart(let msg):
                            if let u = msg.usage {
                                usage = TokenUsage(inputTokens: u.inputTokens, outputTokens: u.outputTokens)
                            }

                        case .messageDelta(_, let deltaUsage):
                            if let u = deltaUsage {
                                let existing = usage ?? TokenUsage(inputTokens: 0, outputTokens: 0)
                                usage = TokenUsage(
                                    inputTokens: existing.inputTokens,
                                    outputTokens: existing.outputTokens + u.outputTokens
                                )
                            }

                        case .messageStop:
                            let toolCalls = accumulatedToolCalls.values.map { accumulator in
                                ToolCall(id: accumulator.id, name: accumulator.name, arguments: accumulator.arguments)
                            }

                            let finishReason: FinishReason = toolCalls.isEmpty ? .stop : .toolUse

                            let response = LLMResponse(
                                content: accumulatedContent.isEmpty ? nil : accumulatedContent,
                                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                                finishReason: finishReason,
                                usage: usage
                            )
                            continuation.yield(.done(response))

                        case .error(let error):
                            throw AgentError.providerError(error.message)

                        case .ping:
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    if let agentError = error as? AgentError {
                        continuation.finish(throwing: agentError)
                    } else {
                        continuation.finish(throwing: AgentError.unknown(error))
                    }
                }
            }
        }
    }

    // MARK: - Request Building

    private func buildAnthropicRequest(from request: LLMRequest) throws -> AnthropicMessagesRequest {
        var systemPrompt: String?
        var anthropicMessages: [AnthropicMessage] = []

        for message in request.messages {
            switch message.role {
            case .system:
                systemPrompt = message.content

            case .user:
                anthropicMessages.append(AnthropicMessage(
                    role: "user",
                    content: [.text(message.content)]
                ))

            case .assistant:
                var content: [AnthropicContentBlock] = []
                if !message.content.isEmpty {
                    content.append(.text(message.content))
                }
                if let toolCalls = message.toolCalls {
                    for call in toolCalls {
                        content.append(.toolUse(
                            id: call.id,
                            name: call.name,
                            input: try parseJSON(call.arguments)
                        ))
                    }
                }
                anthropicMessages.append(AnthropicMessage(role: "assistant", content: content))

            case .tool:
                guard let toolCallId = message.toolCallId else { continue }
                anthropicMessages.append(AnthropicMessage(
                    role: "user",
                    content: [.toolResult(toolUseId: toolCallId, content: message.content)]
                ))
            }
        }

        var tools: [AnthropicTool]?
        if let requestTools = request.tools, !requestTools.isEmpty {
            tools = requestTools.map { def in
                AnthropicTool(
                    name: def.name,
                    description: def.description,
                    inputSchema: def.inputSchema
                )
            }
        }

        return AnthropicMessagesRequest(
            model: request.model,
            messages: anthropicMessages,
            system: systemPrompt,
            maxTokens: request.maxTokens ?? 4096,
            temperature: request.temperature,
            tools: tools,
            stream: false
        )
    }

    private func buildURLRequest(for request: AnthropicMessagesRequest, streaming: Bool) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/messages")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        if streaming {
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        return urlRequest
    }

    private func performRequest(_ request: AnthropicMessagesRequest) async throws -> (Data, URLResponse) {
        let urlRequest = try buildURLRequest(for: request, streaming: false)
        return try await session.data(for: urlRequest)
    }

    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        guard (200...299).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(AnthropicError.self, from: data) {
                switch response.statusCode {
                case 401:
                    throw AgentError.authenticationFailed
                case 429:
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init)
                    throw AgentError.rateLimited(retryAfter: retryAfter)
                default:
                    throw AgentError.providerError(error.error.message)
                }
            }
            throw AgentError.providerError("HTTP \(response.statusCode)")
        }
    }

    private func convertToLLMResponse(_ response: AnthropicMessagesResponse) -> LLMResponse {
        var content: String?
        var toolCalls: [ToolCall] = []

        for block in response.content {
            switch block {
            case .text(let text):
                content = text
            case .toolUse(let id, let name, let input):
                if let inputData = try? JSONSerialization.data(withJSONObject: input),
                   let inputString = String(data: inputData, encoding: .utf8) {
                    toolCalls.append(ToolCall(id: id, name: name, arguments: inputString))
                }
            case .toolResult:
                break
            }
        }

        let finishReason: FinishReason
        switch response.stopReason {
        case "end_turn": finishReason = .stop
        case "tool_use": finishReason = .toolUse
        case "max_tokens": finishReason = .maxTokens
        case "stop_sequence": finishReason = .stopSequence
        default: finishReason = .stop
        }

        let usage = TokenUsage(
            inputTokens: response.usage.inputTokens,
            outputTokens: response.usage.outputTokens
        )

        return LLMResponse(
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls,
            finishReason: finishReason,
            usage: usage
        )
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        guard let data = string.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

// MARK: - Helpers

private struct ToolCallAccumulator {
    let id: String
    let name: String
    var arguments: String = ""
}
