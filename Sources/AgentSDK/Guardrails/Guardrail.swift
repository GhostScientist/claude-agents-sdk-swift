import Foundation

// MARK: - GuardrailResult

/// The outcome of a guardrail validation check.
///
/// Guardrails return one of three results:
/// - ``passed``: Content is valid and can proceed unchanged
/// - ``modified(newContent:reason:)``: Content was adjusted to comply
/// - ``blocked(reason:)``: Content was rejected entirely
///
/// ## Example
///
/// ```swift
/// func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult {
///     if input.count > 10000 {
///         return .blocked(reason: "Input too long")
///     }
///     if input.contains("badword") {
///         let cleaned = input.replacingOccurrences(of: "badword", with: "***")
///         return .modified(newContent: cleaned, reason: "Profanity filtered")
///     }
///     return .passed
/// }
/// ```
public enum GuardrailResult: Sendable {
    /// Content passed validation
    case passed

    /// Content was modified to comply
    case modified(newContent: String, reason: String)

    /// Content was blocked
    case blocked(reason: String)

    /// Whether the content can proceed
    public var canProceed: Bool {
        switch self {
        case .passed, .modified: return true
        case .blocked: return false
        }
    }

    /// Get the content to use (original or modified)
    public func content(original: String) -> String? {
        switch self {
        case .passed: return original
        case .modified(let newContent, _): return newContent
        case .blocked: return nil
        }
    }
}

// MARK: - InputGuardrail

/// A safety mechanism that validates user input before it reaches the LLM.
///
/// Input guardrails run before each message is sent to the LLM, allowing you to:
/// - Block malicious or inappropriate content
/// - Sanitize or modify input for safety
/// - Enforce content policies
/// - Limit input length
///
/// ## Creating Input Guardrails
///
/// ### Using the Convenience Function
///
/// ```swift
/// let profanityFilter = inputGuardrail(name: "profanity-filter") { input, context in
///     if containsProfanity(input) {
///         return .blocked(reason: "Message contains inappropriate language")
///     }
///     return .passed
/// }
/// ```
///
/// ### Conforming to the Protocol
///
/// ```swift
/// struct ContentModerationGuardrail: InputGuardrail {
///     let name = "content-moderation"
///     let moderationService: ModerationService
///
///     func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult {
///         let result = try await moderationService.check(input)
///         if result.isBlocked {
///             return .blocked(reason: result.reason)
///         }
///         return .passed
///     }
/// }
/// ```
///
/// ## Adding to Agents
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Safe Assistant",
///     instructions: "Be helpful and safe.",
///     inputGuardrails: [
///         MaxLengthGuardrail(maxLength: 10000),
///         profanityFilter
///     ]
/// )
/// ```
public protocol InputGuardrail: Sendable {
    var name: String { get }
    func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult
}

// MARK: - OutputGuardrail

/// A safety mechanism that validates LLM output before returning it to the user.
///
/// Output guardrails run after the LLM generates a response, allowing you to:
/// - Block responses containing sensitive information
/// - Redact PII (personally identifiable information)
/// - Ensure compliance with content policies
/// - Modify or filter inappropriate content
///
/// ## Example
///
/// ```swift
/// let piiRedactor = outputGuardrail(name: "pii-redactor") { output, context in
///     if let redacted = redactPII(output) {
///         return .modified(newContent: redacted, reason: "PII removed")
///     }
///     return .passed
/// }
///
/// let agent = Agent<EmptyContext>(
///     name: "Support Agent",
///     instructions: "Help customers with their accounts.",
///     outputGuardrails: [piiRedactor]
/// )
/// ```
public protocol OutputGuardrail: Sendable {
    var name: String { get }
    func validate(_ output: String, context: any AgentContext) async throws -> GuardrailResult
}

// MARK: - Closure-based Guardrails

/// A closure-based implementation of ``InputGuardrail``.
///
/// Use ``inputGuardrail(name:_:)`` to create instances of this type.
public struct ClosureInputGuardrail: InputGuardrail {
    public let name: String
    private let validator: @Sendable (String, any AgentContext) async throws -> GuardrailResult

    public init(
        name: String,
        validator: @escaping @Sendable (String, any AgentContext) async throws -> GuardrailResult
    ) {
        self.name = name
        self.validator = validator
    }

    public func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult {
        try await validator(input, context)
    }
}

/// A closure-based implementation of ``OutputGuardrail``.
///
/// Use ``outputGuardrail(name:_:)`` to create instances of this type.
public struct ClosureOutputGuardrail: OutputGuardrail {
    public let name: String
    private let validator: @Sendable (String, any AgentContext) async throws -> GuardrailResult

    public init(
        name: String,
        validator: @escaping @Sendable (String, any AgentContext) async throws -> GuardrailResult
    ) {
        self.name = name
        self.validator = validator
    }

    public func validate(_ output: String, context: any AgentContext) async throws -> GuardrailResult {
        try await validator(output, context)
    }
}

// MARK: - Convenience Functions

/// Creates an input guardrail from a closure.
///
/// This is the recommended way to create simple input guardrails:
///
/// ```swift
/// let lengthCheck = inputGuardrail(name: "length-check") { input, context in
///     if input.count > 5000 {
///         return .blocked(reason: "Message too long")
///     }
///     return .passed
/// }
/// ```
///
/// - Parameters:
///   - name: A unique name for the guardrail (used in logs and events).
///   - validator: A closure that validates the input and returns a ``GuardrailResult``.
/// - Returns: An input guardrail that can be added to an agent.
public func inputGuardrail(
    name: String,
    _ validator: @escaping @Sendable (String, any AgentContext) async throws -> GuardrailResult
) -> some InputGuardrail {
    ClosureInputGuardrail(name: name, validator: validator)
}

/// Creates an output guardrail from a closure.
///
/// This is the recommended way to create simple output guardrails:
///
/// ```swift
/// let sensitiveDataFilter = outputGuardrail(name: "sensitive-data") { output, context in
///     if output.contains(apiKey) {
///         return .blocked(reason: "Response contains sensitive data")
///     }
///     return .passed
/// }
/// ```
///
/// - Parameters:
///   - name: A unique name for the guardrail (used in logs and events).
///   - validator: A closure that validates the output and returns a ``GuardrailResult``.
/// - Returns: An output guardrail that can be added to an agent.
public func outputGuardrail(
    name: String,
    _ validator: @escaping @Sendable (String, any AgentContext) async throws -> GuardrailResult
) -> some OutputGuardrail {
    ClosureOutputGuardrail(name: name, validator: validator)
}

// MARK: - Built-in Guardrails

/// A guardrail that enforces maximum content length.
///
/// `MaxLengthGuardrail` can validate both input and output. It can either
/// block content exceeding the limit or optionally truncate it.
///
/// ## Example
///
/// ```swift
/// // Block long inputs
/// let strictLimit = MaxLengthGuardrail(maxLength: 10000)
///
/// // Truncate instead of blocking
/// let softLimit = MaxLengthGuardrail(maxLength: 5000, truncate: true)
///
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "Help users.",
///     inputGuardrails: [strictLimit],
///     outputGuardrails: [softLimit]
/// )
/// ```
public struct MaxLengthGuardrail: InputGuardrail, OutputGuardrail {
    public let name: String
    public let maxLength: Int
    public let truncate: Bool

    public init(maxLength: Int, truncate: Bool = false) {
        self.name = "MaxLength(\(maxLength))"
        self.maxLength = maxLength
        self.truncate = truncate
    }

    public func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult {
        if input.count <= maxLength {
            return .passed
        }
        if truncate {
            let truncated = String(input.prefix(maxLength))
            return .modified(newContent: truncated, reason: "Content truncated to \(maxLength) characters")
        }
        return .blocked(reason: "Content exceeds maximum length of \(maxLength) characters")
    }
}

/// A guardrail that blocks content matching specified patterns.
///
/// `BlockPatternGuardrail` checks for substring matches against a list
/// of blocked patterns. This is useful for filtering profanity, sensitive
/// terms, or other unwanted content.
///
/// ## Example
///
/// ```swift
/// let contentFilter = BlockPatternGuardrail(
///     name: "content-filter",
///     patterns: ["secret", "confidential", "internal"],
///     caseSensitive: false
/// )
///
/// let agent = Agent<EmptyContext>(
///     name: "Public Assistant",
///     instructions: "Help external users.",
///     outputGuardrails: [contentFilter]
/// )
/// ```
public struct BlockPatternGuardrail: InputGuardrail, OutputGuardrail {
    public let name: String
    public let patterns: [String]
    public let caseSensitive: Bool

    public init(name: String = "BlockPattern", patterns: [String], caseSensitive: Bool = false) {
        self.name = name
        self.patterns = patterns
        self.caseSensitive = caseSensitive
    }

    public func validate(_ input: String, context: any AgentContext) async throws -> GuardrailResult {
        let checkInput = caseSensitive ? input : input.lowercased()
        for pattern in patterns {
            let checkPattern = caseSensitive ? pattern : pattern.lowercased()
            if checkInput.contains(checkPattern) {
                return .blocked(reason: "Content contains blocked pattern")
            }
        }
        return .passed
    }
}
