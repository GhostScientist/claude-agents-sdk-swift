import Foundation

/// Claude model identifiers
public enum ClaudeModel: String, Sendable, CaseIterable {
    // Claude 4.5 family (Latest - December 2025)
    case claude45Opus = "claude-opus-4-5-20251101"
    case claude45Sonnet = "claude-sonnet-4-5-20250929"
    case claude45Haiku = "claude-haiku-4-5-20251001"

    // Claude 3.5 family (Legacy)
    case claude35Sonnet = "claude-3-5-sonnet-20241022"
    case claude35Haiku = "claude-3-5-haiku-20241022"

    /// User-friendly display name
    public var displayName: String {
        switch self {
        case .claude45Opus: return "Claude Opus 4.5"
        case .claude45Sonnet: return "Claude Sonnet 4.5"
        case .claude45Haiku: return "Claude Haiku 4.5"
        case .claude35Sonnet: return "Claude 3.5 Sonnet"
        case .claude35Haiku: return "Claude 3.5 Haiku"
        }
    }

    /// Maximum context window tokens
    public var maxContextTokens: Int {
        switch self {
        case .claude45Opus, .claude45Sonnet, .claude45Haiku: return 200_000
        case .claude35Sonnet, .claude35Haiku: return 200_000
        }
    }

    /// Maximum output tokens
    public var maxOutputTokens: Int {
        switch self {
        case .claude45Opus, .claude45Sonnet: return 16_000
        case .claude45Haiku: return 8_192
        case .claude35Sonnet, .claude35Haiku: return 8_192
        }
    }

    /// Recommended model for most use cases
    public static var recommended: ClaudeModel { .claude45Sonnet }
}
