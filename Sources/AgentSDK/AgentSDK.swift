// AgentSDK.swift
// AgentSDK
//
// A Swift framework for building AI agents with tool calling,
// multi-agent orchestration, and Apple platform integration.

@_exported import Foundation

// MARK: - Framework Overview

/// # AgentSDK
///
/// A modern Swift framework for building AI-powered agents with support for:
/// - **Tool Calling**: Define tools that LLMs can invoke
/// - **Multi-Agent**: Orchestrate multiple specialized agents via handoffs
/// - **Guardrails**: Validate inputs and outputs to ensure safe operation
/// - **Streaming**: Real-time response streaming with SwiftUI integration
/// - **MCP Support**: Connect to Model Context Protocol servers
/// - **Provider Agnostic**: Works with Claude, and extensible to other LLMs
///
/// ## Quick Start
///
/// ```swift
/// import AgentSDK
/// import ClaudeProvider
///
/// // Create a simple agent
/// let agent = Agent<EmptyContext>(
///     name: "Assistant",
///     instructions: "You are a helpful assistant."
/// )
///
/// // Run with Claude
/// let provider = ClaudeProvider(apiKey: "your-api-key")
/// let runner = Runner(provider: provider)
/// let result = try await runner.run(agent, input: "Hello!")
/// print(result.output)
/// ```
///
/// ## Key Components
///
/// - ``Agent``: Defines an agent's personality, tools, and capabilities
/// - ``Runner``: Executes agents and manages the conversation loop
/// - ``Tool``: Protocol for defining tools that agents can use
/// - ``LLMProvider``: Protocol for LLM backends (Claude, etc.)
/// - ``MCPToolProvider``: Connects to MCP servers for dynamic tools
///
/// ## Topics
///
/// ### Essentials
/// - ``Agent``
/// - ``Runner``
/// - ``RunResult``
///
/// ### Tools
/// - ``Tool``
/// - ``FunctionTool``
/// - ``JSONSchema``
///
/// ### Multi-Agent
/// - ``Handoff``
///
/// ### Safety
/// - ``InputGuardrail``
/// - ``OutputGuardrail``
/// - ``GuardrailResult``
///
/// ### Streaming
/// - ``AgentEvent``
/// - ``LLMStreamEvent``
///
/// ### MCP Integration
/// - ``MCPClient``
/// - ``MCPToolProvider``
///
/// ### Context
/// - ``AgentContext``
/// - ``EmptyContext``
public enum AgentSDKInfo {
    /// The current version of the AgentSDK framework.
    public static let version = "0.1.0"

    /// The minimum supported iOS version.
    public static let minimumIOSVersion = "17.0"

    /// The minimum supported macOS version.
    public static let minimumMacOSVersion = "14.0"
}
