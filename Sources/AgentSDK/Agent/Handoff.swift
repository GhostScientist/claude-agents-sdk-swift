import Foundation

// MARK: - Handoff

/// Enables an agent to delegate tasks to another specialized agent.
///
/// Handoffs are the foundation of multi-agent workflows. They allow a "triage" or
/// "router" agent to analyze a user's request and delegate it to the most appropriate
/// specialized agent.
///
/// ## How Handoffs Work
///
/// When you add handoffs to an agent, they become available as tools the LLM can call.
/// When the LLM decides to hand off:
/// 1. It calls the handoff tool with a reason
/// 2. The ``Runner`` switches to the target agent
/// 3. The conversation continues with the new agent's instructions
///
/// ## Basic Usage
///
/// ```swift
/// // Create specialized agents
/// let billingAgent = Agent<EmptyContext>(
///     name: "Billing",
///     instructions: "Handle billing questions. Be clear about pricing."
/// )
///
/// let technicalAgent = Agent<EmptyContext>(
///     name: "Technical",
///     instructions: "Handle technical support. Be patient and thorough."
/// )
///
/// // Create a triage agent that routes to specialists
/// let triageAgent = Agent<EmptyContext>(
///     name: "Support",
///     instructions: """
///         You are the first point of contact for customer support.
///         Determine what the user needs and route them to the right team.
///         """,
///     handoffs: [
///         Handoff(description: "For billing and payment questions", to: billingAgent),
///         Handoff(description: "For technical issues and bugs", to: technicalAgent)
///     ]
/// )
/// ```
///
/// ## Custom Handoff Names
///
/// By default, handoff names are generated from the agent name (e.g., `handoff_to_billing`).
/// You can provide custom names:
///
/// ```swift
/// Handoff(
///     name: "escalate_to_specialist",
///     description: "For complex technical issues",
///     to: seniorEngineerAgent
/// )
/// ```
///
/// ## Preventing Cycles
///
/// The ``Runner`` automatically detects and prevents handoff cycles. If Agent A
/// hands off to Agent B, which tries to hand back to Agent A, an error is thrown.
public struct Handoff: Sendable {
    /// Name used to invoke this handoff (becomes a tool name)
    public let name: String

    /// Description of when to use this handoff
    public let description: String

    /// The agent to hand off to
    public let targetAgent: AnyAgent

    public init<A: AgentProtocol>(
        name: String? = nil,
        description: String,
        to agent: A
    ) {
        self.name = name ?? "handoff_to_\(agent.name.lowercased().replacingOccurrences(of: " ", with: "_"))"
        self.description = description
        self.targetAgent = AnyAgent(agent)
    }

    /// Convert handoff to a tool definition for LLM
    public var toolDefinition: ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Hand off to \(targetAgent.name): \(description)",
            inputSchema: .object(
                properties: [
                    "reason": .string("Reason for handing off to this agent")
                ],
                required: ["reason"]
            )
        )
    }
}

// MARK: - HandoffResult

/// Information about a completed handoff between agents.
///
/// This type is used internally by the ``Runner`` to track handoff history
/// and is included in ``AgentEvent/handoff(from:to:reason:)`` events.
public struct HandoffResult: Sendable {
    public let fromAgent: String
    public let toAgent: String
    public let reason: String

    public init(fromAgent: String, toAgent: String, reason: String) {
        self.fromAgent = fromAgent
        self.toAgent = toAgent
        self.reason = reason
    }
}

/// Input arguments for a handoff tool call
public struct HandoffArguments: Codable, Sendable {
    public let reason: String
}
