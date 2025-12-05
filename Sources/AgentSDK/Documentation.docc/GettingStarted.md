# Getting Started

Learn how to create your first AI agent with AgentSDK.

## Overview

This guide walks you through creating a basic agent, adding tools, and running conversations.

## Installation

Add AgentSDK to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/GhostScientist/claude-agents-sdk-swift.git", from: "0.1.0")
]
```

Then add the products to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "AgentSDK",
        "ClaudeProvider",
        "AgentSDKApple",  // Optional: SwiftUI integration
    ]
)
```

## Creating Your First Agent

An agent is defined by its name, instructions, and optional tools:

```swift
import AgentSDK
import ClaudeProvider

let agent = Agent<EmptyContext>(
    name: "Assistant",
    instructions: """
        You are a helpful assistant. Be concise and friendly.
        Always greet users warmly.
        """
)
```

## Running the Agent

Use a ``Runner`` to execute the agent:

```swift
let provider = ClaudeProvider(apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!)
let runner = Runner(provider: provider)

// Run to completion
let result = try await runner.run(agent, input: "Hello!")
print(result.output)
```

## Streaming Responses

For real-time UI updates, use streaming:

```swift
for try await event in runner.stream(agent, input: "Tell me a joke") {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .completed(let result):
        print("\n\nTokens used: \(result.tokenUsage?.totalTokens ?? 0)")
    default:
        break
    }
}
```

## Next Steps

- Learn to create tools in <doc:CreatingTools>
- Build multi-agent workflows in <doc:MultiAgentWorkflows>
