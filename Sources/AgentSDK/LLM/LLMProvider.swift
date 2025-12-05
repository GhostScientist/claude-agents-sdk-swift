import Foundation

// MARK: - LLMProvider

/// Protocol for integrating language models with AgentSDK.
///
/// `LLMProvider` is the abstraction layer that allows AgentSDK to work with
/// different LLM backends. The SDK ships with ``ClaudeProvider`` for Anthropic's
/// Claude, but you can implement this protocol to support other models.
///
/// ## Overview
///
/// An LLM provider must support:
/// - A default model to use when none is specified
/// - Completion requests that return a full response
/// - Streaming requests for real-time text generation
///
/// ## Using Built-in Providers
///
/// ```swift
/// import ClaudeProvider
///
/// let provider = ClaudeProvider(apiKey: "your-api-key")
/// let runner = Runner(provider: provider)
/// ```
///
/// ## Implementing a Custom Provider
///
/// ```swift
/// struct MyLLMProvider: LLMProvider {
///     let defaultModel = "my-model-v1"
///
///     func complete(_ request: LLMRequest) async throws -> LLMResponse {
///         // Make API call to your LLM
///         let result = try await myAPI.complete(
///             model: request.model,
///             messages: request.messages,
///             tools: request.tools
///         )
///         return LLMResponse(
///             content: result.text,
///             toolCalls: result.toolCalls,
///             finishReason: .stop,
///             usage: TokenUsage(inputTokens: result.inputTokens, outputTokens: result.outputTokens)
///         )
///     }
///
///     // Streaming has a default implementation, but override for true streaming
///     func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
///         // ... implement streaming
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Required Members
/// - ``defaultModel``
/// - ``complete(_:)``
///
/// ### Optional Members
/// - ``stream(_:)``
public protocol LLMProvider: Sendable {
    /// The default model to use if none specified
    var defaultModel: String { get }

    /// Send a completion request and receive a full response
    func complete(_ request: LLMRequest) async throws -> LLMResponse

    /// Send a completion request and receive streaming events
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

// Default streaming implementation for providers that don't support it
extension LLMProvider {
    public func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await self.complete(request)
                    if let content = response.content {
                        continuation.yield(.textDelta(content))
                    }
                    continuation.yield(.done(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - LLMRequest

/// A request to an LLM provider.
///
/// This struct encapsulates all the parameters needed to make a request to an LLM.
/// The ``Runner`` constructs these automatically, but you can create them manually
/// when implementing custom ``LLMProvider``s.
public struct LLMRequest: Sendable {
    public let model: String
    public let messages: [Message]
    public let tools: [ToolDefinition]?
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let stopSequences: [String]?

    public init(
        model: String,
        messages: [Message],
        tools: [ToolDefinition]? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stopSequences: [String]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
    }
}

// MARK: - LLMResponse

/// A response from an LLM provider.
///
/// This struct contains the LLM's output, including any text content,
/// tool calls it wants to make, the reason it stopped generating, and
/// token usage statistics.
public struct LLMResponse: Sendable {
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let finishReason: FinishReason
    public let usage: TokenUsage?

    public init(
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        finishReason: FinishReason,
        usage: TokenUsage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }
}

// MARK: - FinishReason

/// The reason an LLM stopped generating content.
///
/// This helps determine what action to take next:
/// - ``stop``: The model finished naturally, response is complete
/// - ``toolUse``: The model wants to call tools, process them and continue
/// - ``maxTokens``: Output was truncated, may need to continue
/// - ``stopSequence``: A stop sequence was hit
/// - ``error(_:)``: An error occurred
public enum FinishReason: Sendable, Codable, Hashable {
    case stop
    case toolUse
    case maxTokens
    case stopSequence
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case type, message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "end_turn", "stop": self = .stop
        case "tool_use": self = .toolUse
        case "max_tokens": self = .maxTokens
        case "stop_sequence": self = .stopSequence
        default: self = .error(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .stop: try container.encode("stop")
        case .toolUse: try container.encode("tool_use")
        case .maxTokens: try container.encode("max_tokens")
        case .stopSequence: try container.encode("stop_sequence")
        case .error(let message): try container.encode("error: \(message)")
        }
    }
}

// MARK: - TokenUsage

/// Token consumption statistics from an LLM request.
///
/// Use this to track API costs and monitor usage:
///
/// ```swift
/// let result = try await runner.run(agent, input: "Hello")
/// if let usage = result.tokenUsage {
///     print("Input: \(usage.inputTokens), Output: \(usage.outputTokens)")
///     print("Total: \(usage.totalTokens)")
/// }
/// ```
public struct TokenUsage: Sendable, Codable, Hashable {
    public let inputTokens: Int
    public let outputTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - LLMStreamEvent

/// Events emitted by an LLM provider during streaming.
///
/// These low-level events are used internally by the ``Runner`` to construct
/// higher-level ``AgentEvent``s. If you're implementing a custom ``LLMProvider``,
/// you'll emit these events during streaming.
public enum LLMStreamEvent: Sendable {
    case textDelta(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallComplete(id: String)
    case done(LLMResponse)
}
