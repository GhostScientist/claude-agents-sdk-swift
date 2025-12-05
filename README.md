# AgentSDK for Swift

A modern Swift framework for building AI-powered agents with tool calling, multi-agent orchestration, and seamless Apple platform integration.

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%2B%20|%20macOS%2014%2B-blue.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- **Agent Loop** - Automatic conversation management with tool calling
- **Tool System** - Define tools with `@Tool` macro or protocol conformance
- **Multi-Agent** - Orchestrate specialized agents via handoffs
- **Guardrails** - Input/output validation for safe operation
- **Streaming** - Real-time response streaming with SwiftUI integration
- **MCP Support** - Connect to Model Context Protocol servers (HuggingFace, etc.)
- **Provider Agnostic** - Works with Claude, extensible to other LLMs
- **Apple Native** - SwiftUI views, App Intents, and Shortcuts support

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Your App                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │    Agent     │    │    Runner    │    │   AgentViewModel     │  │
│  │              │───▶│              │───▶│   (SwiftUI)          │  │
│  │ • name       │    │ • run()      │    │                      │  │
│  │ • instructions    │ • stream()   │    │ • messages           │  │
│  │ • tools      │    │              │    │ • isRunning          │  │
│  │ • handoffs   │    └──────┬───────┘    └──────────────────────┘  │
│  │ • guardrails │           │                                       │
│  └──────────────┘           │                                       │
│                             ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                      LLMProvider                              │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                    │  │
│  │  │  ClaudeProvider │  │  (Your Custom)  │                    │  │
│  │  │                 │  │    Provider     │                    │  │
│  │  └────────┬────────┘  └─────────────────┘                    │  │
│  └───────────┼──────────────────────────────────────────────────┘  │
│              │                                                      │
│              ▼                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                        Tools                                  │  │
│  │  ┌───────────┐  ┌───────────┐  ┌────────────────────────┐   │  │
│  │  │ Built-in  │  │  Custom   │  │   MCPToolProvider      │   │  │
│  │  │  Tools    │  │  Tools    │  │   (MCP Servers)        │   │  │
│  │  └───────────┘  └───────────┘  └────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Installation

Add AgentSDK to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/agent-sdk-swift.git", from: "0.1.0")
]
```

Then add the products you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "AgentSDK",           // Core framework
        "ClaudeProvider",     // Anthropic Claude integration
        "AgentSDKApple",      // SwiftUI & App Intents (optional)
    ]
)
```

## Quick Start

### 1. Basic Agent

```swift
import AgentSDK
import ClaudeProvider

// Create an agent
let agent = Agent<EmptyContext>(
    name: "Assistant",
    instructions: "You are a helpful assistant."
)

// Run with Claude
let provider = ClaudeProvider(apiKey: "your-api-key")
let runner = Runner(provider: provider)

let result = try await runner.run(agent, input: "Hello!")
print(result.output)
```

### 2. Agent with Tools

```swift
// Define a tool using FunctionTool
let weatherTool = FunctionTool(
    name: "get_weather",
    description: "Get the current weather for a city",
    parameters: .object(
        properties: [
            "city": .string("The city name"),
            "units": .string("Temperature units: celsius or fahrenheit")
        ],
        required: ["city"]
    )
) { arguments, context in
    let city = arguments["city"] as? String ?? "Unknown"
    return "The weather in \(city) is 72°F and sunny."
}

let agent = Agent<EmptyContext>(
    name: "Weather Assistant",
    instructions: "Help users check the weather.",
    tools: [weatherTool]
)
```

### 3. Multi-Agent with Handoffs

```swift
let billingAgent = Agent<EmptyContext>(
    name: "Billing",
    instructions: "Handle billing questions."
)

let technicalAgent = Agent<EmptyContext>(
    name: "Technical",
    instructions: "Handle technical support."
)

let triageAgent = Agent<EmptyContext>(
    name: "Triage",
    instructions: "Route users to the right department.",
    handoffs: [
        Handoff(name: "billing", description: "Billing questions", agent: billingAgent),
        Handoff(name: "technical", description: "Technical issues", agent: technicalAgent)
    ]
)
```

### 4. Streaming Responses

```swift
for try await event in runner.stream(agent, input: "Tell me a story") {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolCallStarted(let name, _):
        print("\n[Calling tool: \(name)]")
    case .completed(let result):
        print("\n\nDone! Tokens used: \(result.tokenUsage?.totalTokens ?? 0)")
    default:
        break
    }
}
```

### 5. SwiftUI Integration

```swift
import AgentSDKApple

struct ChatView: View {
    @State private var viewModel: AgentViewModel<Agent<EmptyContext>>

    init() {
        let agent = Agent<EmptyContext>(
            name: "Assistant",
            instructions: "You are helpful."
        )
        let provider = ClaudeProvider(apiKey: apiKey)
        _viewModel = State(initialValue: AgentViewModel(agent: agent, provider: provider))
    }

    var body: some View {
        AgentChatView(viewModel: viewModel)
    }
}
```

### 6. MCP Server Integration

Connect to [Model Context Protocol](https://modelcontextprotocol.io) servers like HuggingFace:

```swift
import AgentSDK

// Create MCP tool provider
let mcpProvider = MCPToolProvider()

// Connect to HuggingFace MCP server
let serverInfo = MCPClient.MCPServerInfo(
    name: "HuggingFace",
    url: URL(string: "https://huggingface.co/mcp")!,
    headers: ["Authorization": "Bearer \(hfToken)"],
    useStreamableHTTP: true
)

let tools = try await mcpProvider.addServer(serverInfo)
print("Connected! Discovered \(tools.count) tools")

// Create agent with MCP tools
let agent = await Agent.withMCPTools(
    name: "HF Assistant",
    instructions: "Help users explore HuggingFace.",
    toolProvider: mcpProvider
)
```

**Supported MCP Transports:**
- **Streamable HTTP** - For modern servers (HuggingFace, Smithery, etc.)
- **SSE** - For legacy Server-Sent Events servers
- **Stdio** - For local MCP servers (macOS only)

### 7. Guardrails

```swift
// Built-in guardrails
let agent = Agent<EmptyContext>(
    name: "Safe Assistant",
    instructions: "Be helpful but safe.",
    inputGuardrails: [
        MaxLengthGuardrail(maxLength: 10000)
    ],
    outputGuardrails: [
        BlockPatternGuardrail(patterns: [sensitivePatterns])
    ]
)

// Custom guardrail
let customGuardrail = inputGuardrail(name: "profanity-filter") { input, context in
    if containsProfanity(input) {
        return .blocked(reason: "Message contains inappropriate language")
    }
    return .passed
}
```

## Package Structure

| Package | Description |
|---------|-------------|
| `AgentSDK` | Core framework with Agent, Runner, Tools, MCP support |
| `ClaudeProvider` | Anthropic Claude API integration |
| `AgentSDKApple` | SwiftUI views and App Intents integration |
| `AgentSDKMacros` | Swift macros for `@Tool` and `@ToolInput` |

## Requirements

- **iOS 17.0+** / **macOS 14.0+**
- **Swift 5.9+**
- **Xcode 15.0+**

## Logging

AgentSDK includes a configurable logging system (disabled by default):

```swift
import AgentSDK

// Enable debug logging during development
AgentLogger.configuration = LoggerConfiguration(
    isEnabled: true,
    minimumLevel: .debug
)
```

## Examples

See the `Examples/` directory for complete sample applications:

- **FlightAgentify** - iOS app demonstrating MCP integration and chat UI

## API Reference

### Core Types

| Type | Description |
|------|-------------|
| `Agent` | Configurable agent with instructions, tools, handoffs, guardrails |
| `Runner` | Executes agents and manages the conversation loop |
| `Tool` | Protocol for callable functions |
| `FunctionTool` | Closure-based tool implementation |
| `Handoff` | Delegate to another specialized agent |
| `LLMProvider` | Protocol for LLM backends (Claude, etc.) |
| `MCPToolProvider` | Connect to MCP servers for dynamic tools |
| `AgentViewModel` | Observable wrapper for SwiftUI |

### Events

| Event | Description |
|-------|-------------|
| `agentStarted` | Agent began processing |
| `textDelta` | Incremental text from LLM |
| `toolCallStarted` | Tool invocation began |
| `toolCallCompleted` | Tool returned result |
| `handoff` | Control transferred to another agent |
| `completed` | Agent finished with final result |

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Inspired by:
- [Claude Agent SDK (TypeScript)](https://docs.anthropic.com/en/docs/claude-code/sdk)
- [OpenAI Agents SDK (Python)](https://github.com/openai/openai-agents-python)
- [Model Context Protocol](https://modelcontextprotocol.io)
