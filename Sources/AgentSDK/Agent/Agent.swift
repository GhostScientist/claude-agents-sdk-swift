// Agent.swift
// AgentSDK
//
// Defines the core Agent type and AgentProtocol.

import Foundation

// MARK: - Agent Protocol

/// A protocol that defines the interface for an AI agent.
///
/// `AgentProtocol` specifies the essential properties that any agent must have,
/// including its identity, capabilities, and safety mechanisms.
///
/// ## Conforming to AgentProtocol
///
/// You can create custom agent types by conforming to this protocol:
///
/// ```swift
/// struct MyCustomAgent: AgentProtocol {
///     let name = "CustomAgent"
///     let instructions = "You are a specialized assistant."
///
///     var tools: [any Tool] {
///         [MyTool(), AnotherTool()]
///     }
/// }
/// ```
///
/// For most use cases, the built-in ``Agent`` struct is sufficient.
///
/// ## Topics
///
/// ### Required Properties
/// - ``name``
/// - ``instructions``
///
/// ### Optional Properties
/// - ``model``
/// - ``tools``
/// - ``handoffs``
/// - ``inputGuardrails``
/// - ``outputGuardrails``
public protocol AgentProtocol: Sendable {
    /// The type of context this agent uses for state management.
    associatedtype Context: AgentContext = EmptyContext

    /// A unique name identifying this agent.
    ///
    /// The name is used for logging, debugging, and identifying the agent
    /// in multi-agent scenarios during handoffs.
    var name: String { get }

    /// System instructions that define the agent's behavior and personality.
    ///
    /// These instructions are sent to the LLM as the system prompt and should
    /// clearly define:
    /// - The agent's role and expertise
    /// - How it should respond to users
    /// - Any constraints or guidelines
    ///
    /// ## Example
    ///
    /// ```swift
    /// let instructions = """
    /// You are a helpful customer support agent for Acme Corp.
    /// Always be polite and professional.
    /// If you don't know the answer, say so and offer to escalate.
    /// """
    /// ```
    var instructions: String { get }

    /// The LLM model to use for this agent, or `nil` to use the provider's default.
    ///
    /// When specified, this overrides the default model configured in the ``LLMProvider``.
    /// Use this to assign different models to different agents based on task complexity.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Use a more capable model for complex reasoning
    /// let complexAgent = Agent<EmptyContext>(
    ///     name: "Analyst",
    ///     instructions: "Perform complex data analysis.",
    ///     model: "claude-opus-4-5-20251101"
    /// )
    /// ```
    var model: String? { get }

    /// Tools available to this agent for performing actions.
    ///
    /// Tools extend the agent's capabilities beyond text generation,
    /// allowing it to perform calculations, fetch data, or interact with external systems.
    var tools: [any Tool] { get }

    /// Other agents that this agent can delegate tasks to.
    ///
    /// Handoffs enable multi-agent workflows where specialized agents
    /// handle specific types of requests.
    var handoffs: [Handoff] { get }

    /// Guardrails that validate user input before processing.
    var inputGuardrails: [any InputGuardrail] { get }

    /// Guardrails that validate agent output before returning to the user.
    var outputGuardrails: [any OutputGuardrail] { get }
}

/// Default implementations for optional agent properties.
extension AgentProtocol {
    public var model: String? { nil }
    public var tools: [any Tool] { [] }
    public var handoffs: [Handoff] { [] }
    public var inputGuardrails: [any InputGuardrail] { [] }
    public var outputGuardrails: [any OutputGuardrail] { [] }
}

// MARK: - Agent

/// A configurable AI agent with tools, guardrails, and handoff capabilities.
///
/// `Agent` is the primary type for defining AI agents in AgentSDK. It provides
/// a flexible, declarative way to configure an agent's behavior, capabilities,
/// and safety mechanisms.
///
/// ## Creating an Agent
///
/// The simplest way to create an agent is with just a name and instructions:
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "You are a helpful assistant."
/// )
/// ```
///
/// ## Adding Tools
///
/// Tools extend what an agent can do. Use the tools parameter or the
/// result builder syntax:
///
/// ```swift
/// // Array syntax
/// let agent = Agent<EmptyContext>(
///     name: "Calculator",
///     instructions: "Help users with math.",
///     tools: [AddTool(), MultiplyTool()]
/// )
///
/// // Result builder syntax
/// let agent = Agent<EmptyContext>(
///     name: "Calculator",
///     instructions: "Help users with math."
/// ) {
///     AddTool()
///     MultiplyTool()
/// }
/// ```
///
/// ## Multi-Agent Workflows
///
/// Use handoffs to delegate to specialized agents:
///
/// ```swift
/// let supportAgent = Agent<EmptyContext>(
///     name: "Support",
///     instructions: "Handle general questions.",
///     handoffs: [
///         Handoff(
///             name: "billing",
///             description: "For billing questions",
///             agent: billingAgent
///         )
///     ]
/// )
/// ```
///
/// ## Safety with Guardrails
///
/// Add guardrails to validate inputs and outputs:
///
/// ```swift
/// let agent = Agent<EmptyContext>(
///     name: "Safe Assistant",
///     instructions: "Be helpful but safe.",
///     inputGuardrails: [MaxLengthGuardrail(maxLength: 1000)],
///     outputGuardrails: [BlockPatternGuardrail(patterns: [dangerousPatterns])]
/// )
/// ```
///
/// ## Fluent API
///
/// Modify agents using the fluent API:
///
/// ```swift
/// let enhanced = baseAgent
///     .using(model: "claude-opus-4-5-20251101")
///     .with(tools: [NewTool()])
/// ```
public struct Agent<Context: AgentContext>: AgentProtocol, Sendable {
    public let name: String
    public let instructions: String
    public let model: String?
    public let tools: [any Tool]
    public let handoffs: [Handoff]
    public let inputGuardrails: [any InputGuardrail]
    public let outputGuardrails: [any OutputGuardrail]

    /// Creates an agent with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: A unique name for the agent.
    ///   - instructions: System prompt defining the agent's behavior.
    ///   - model: Optional model override. Uses provider default if `nil`.
    ///   - tools: Array of tools the agent can use.
    ///   - handoffs: Agents this agent can delegate to.
    ///   - inputGuardrails: Validators for user input.
    ///   - outputGuardrails: Validators for agent output.
    public init(
        name: String,
        instructions: String,
        model: String? = nil,
        tools: [any Tool] = [],
        handoffs: [Handoff] = [],
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = []
    ) {
        self.name = name
        self.instructions = instructions
        self.model = model
        self.tools = tools
        self.handoffs = handoffs
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }

    /// Creates an agent using a result builder for tools.
    ///
    /// This initializer provides a more declarative syntax for defining tools:
    ///
    /// ```swift
    /// let agent = Agent<EmptyContext>(
    ///     name: "Helper",
    ///     instructions: "Help with tasks."
    /// ) {
    ///     SearchTool()
    ///     CalculatorTool()
    ///     if needsAdvancedFeatures {
    ///         AdvancedTool()
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: A unique name for the agent.
    ///   - instructions: System prompt defining the agent's behavior.
    ///   - model: Optional model override.
    ///   - handoffs: Agents this agent can delegate to.
    ///   - inputGuardrails: Validators for user input.
    ///   - outputGuardrails: Validators for agent output.
    ///   - tools: A result builder closure that returns tools.
    public init(
        name: String,
        instructions: String,
        model: String? = nil,
        handoffs: [Handoff] = [],
        inputGuardrails: [any InputGuardrail] = [],
        outputGuardrails: [any OutputGuardrail] = [],
        @ToolsBuilder tools: () -> [any Tool]
    ) {
        self.name = name
        self.instructions = instructions
        self.model = model
        self.tools = tools()
        self.handoffs = handoffs
        self.inputGuardrails = inputGuardrails
        self.outputGuardrails = outputGuardrails
    }
}

// MARK: - AnyAgent

/// A type-erased wrapper for any agent.
///
/// `AnyAgent` allows you to work with agents of different context types
/// in a uniform way. This is useful for collections of heterogeneous agents
/// or when the specific context type doesn't matter.
///
/// ## Example
///
/// ```swift
/// let agents: [AnyAgent] = [
///     AnyAgent(supportAgent),
///     AnyAgent(billingAgent),
///     AnyAgent(technicalAgent)
/// ]
///
/// for agent in agents {
///     print("Agent: \(agent.name)")
/// }
/// ```
public struct AnyAgent: AgentProtocol, @unchecked Sendable {
    public typealias Context = EmptyContext

    public let name: String
    public let instructions: String
    public let model: String?
    public let tools: [any Tool]
    public let handoffs: [Handoff]
    public let inputGuardrails: [any InputGuardrail]
    public let outputGuardrails: [any OutputGuardrail]

    /// Creates a type-erased agent from any agent conforming to ``AgentProtocol``.
    ///
    /// - Parameter agent: The agent to wrap.
    public init<A: AgentProtocol>(_ agent: A) {
        self.name = agent.name
        self.instructions = agent.instructions
        self.model = agent.model
        self.tools = agent.tools
        self.handoffs = agent.handoffs
        self.inputGuardrails = agent.inputGuardrails
        self.outputGuardrails = agent.outputGuardrails
    }
}

// MARK: - Fluent API

extension Agent {
    /// Returns a copy of this agent configured to use the specified model.
    ///
    /// - Parameter model: The model identifier to use.
    /// - Returns: A new agent with the specified model.
    public func using(model: String) -> Agent {
        Agent(
            name: name,
            instructions: instructions,
            model: model,
            tools: tools,
            handoffs: handoffs,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails
        )
    }

    /// Returns a copy of this agent with additional tools.
    ///
    /// - Parameter additionalTools: Tools to add to the agent.
    /// - Returns: A new agent with the combined tools.
    public func with(tools additionalTools: [any Tool]) -> Agent {
        Agent(
            name: name,
            instructions: instructions,
            model: model,
            tools: tools + additionalTools,
            handoffs: handoffs,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails
        )
    }

    /// Returns a copy of this agent with additional handoffs.
    ///
    /// - Parameter additionalHandoffs: Handoffs to add to the agent.
    /// - Returns: A new agent with the combined handoffs.
    public func with(handoffs additionalHandoffs: [Handoff]) -> Agent {
        Agent(
            name: name,
            instructions: instructions,
            model: model,
            tools: tools,
            handoffs: handoffs + additionalHandoffs,
            inputGuardrails: inputGuardrails,
            outputGuardrails: outputGuardrails
        )
    }
}
