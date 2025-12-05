# ``AgentSDK``

Build AI-powered agents with tool calling, multi-agent orchestration, and seamless Apple platform integration.

## Overview

AgentSDK is a Swift framework for building intelligent agents that can:

- Execute multi-turn conversations with LLMs
- Call tools to perform actions and retrieve information
- Hand off between specialized agents
- Validate inputs and outputs with guardrails
- Connect to MCP servers for dynamic tool discovery

## Getting Started

Create your first agent in just a few lines:

```swift
import AgentSDK
import ClaudeProvider

let agent = Agent<EmptyContext>(
    name: "Assistant",
    instructions: "You are a helpful assistant."
)

let provider = ClaudeProvider(apiKey: "your-api-key")
let runner = Runner(provider: provider)

let result = try await runner.run(agent, input: "Hello!")
print(result.output)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CreatingTools>
- <doc:MultiAgentWorkflows>

### Core Types

- ``Agent``
- ``Runner``
- ``Tool``
- ``FunctionTool``
- ``Handoff``

### LLM Integration

- ``LLMProvider``
- ``LLMRequest``
- ``LLMResponse``
- ``TokenUsage``

### Context & State

- ``AgentContext``
- ``EmptyContext``
- ``CustomContext``

### Safety

- ``InputGuardrail``
- ``OutputGuardrail``
- ``GuardrailResult``
- ``MaxLengthGuardrail``
- ``BlockPatternGuardrail``

### Events & Results

- ``AgentEvent``
- ``RunResult``

### MCP Integration

- ``MCPToolProvider``
- ``MCPClient``
- ``MCPTool``

### Macros

- ``Tool(_:)``
- ``ToolInput()``

### Logging

- ``AgentLogger``
- ``LoggerConfiguration``
