import Foundation

/// Errors that can occur during agent execution
public enum AgentError: Error, Sendable {
    // Execution errors
    case maxTurnsExceeded(turns: Int)
    case cancelled
    case timeout

    // Tool errors
    case toolNotFound(name: String)
    case toolExecutionFailed(tool: String, reason: String)
    case invalidToolArguments(tool: String, reason: String)

    // Guardrail errors
    case inputBlocked(guardrail: String, reason: String)
    case outputBlocked(guardrail: String, reason: String)

    // Provider errors
    case providerError(String)
    case rateLimited(retryAfter: TimeInterval?)
    case authenticationFailed
    case invalidResponse(String)

    // Handoff errors
    case handoffFailed(from: String, to: String, reason: String)
    case cyclicHandoff(agents: [String])

    // Configuration errors
    case invalidConfiguration(String)
    case missingAPIKey

    // Unknown
    case unknown(Error)
}

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .maxTurnsExceeded(let turns):
            return "Agent exceeded maximum turns (\(turns))"
        case .cancelled:
            return "Agent execution was cancelled"
        case .timeout:
            return "Agent execution timed out"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .toolExecutionFailed(let tool, let reason):
            return "Tool '\(tool)' failed: \(reason)"
        case .invalidToolArguments(let tool, let reason):
            return "Invalid arguments for tool '\(tool)': \(reason)"
        case .inputBlocked(let guardrail, let reason):
            return "Input blocked by \(guardrail): \(reason)"
        case .outputBlocked(let guardrail, let reason):
            return "Output blocked by \(guardrail): \(reason)"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Retry after \(retry) seconds"
            }
            return "Rate limited"
        case .authenticationFailed:
            return "Authentication failed"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .handoffFailed(let from, let to, let reason):
            return "Handoff from '\(from)' to '\(to)' failed: \(reason)"
        case .cyclicHandoff(let agents):
            return "Cyclic handoff detected: \(agents.joined(separator: " -> "))"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .missingAPIKey:
            return "API key not configured"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}
