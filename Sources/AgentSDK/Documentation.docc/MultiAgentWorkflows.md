# Multi-Agent Workflows

Build sophisticated workflows with specialized agents that hand off to each other.

## Overview

Multi-agent workflows allow you to create specialized agents for different tasks and route users to the right one. A "triage" agent analyzes requests and delegates to specialists.

## Creating Specialized Agents

First, define agents for specific domains:

```swift
let billingAgent = Agent<EmptyContext>(
    name: "Billing",
    instructions: """
        You are a billing specialist. Help users with:
        - Payment questions
        - Invoice inquiries
        - Subscription changes
        - Refund requests

        Be clear about pricing and policies.
        """
)

let technicalAgent = Agent<EmptyContext>(
    name: "Technical",
    instructions: """
        You are a technical support engineer. Help users with:
        - Bug reports
        - Configuration issues
        - Integration problems
        - Performance questions

        Be patient and thorough. Ask clarifying questions.
        """
)
```

## Creating a Triage Agent

Create a router agent with handoffs:

```swift
let triageAgent = Agent<EmptyContext>(
    name: "Support",
    instructions: """
        You are the first point of contact for customer support.

        Your job is to:
        1. Greet the user warmly
        2. Understand their needs
        3. Route them to the right specialist

        For billing/payment questions → hand off to Billing
        For technical issues/bugs → hand off to Technical
        For general questions → answer directly
        """,
    handoffs: [
        Handoff(description: "For billing and payment questions", to: billingAgent),
        Handoff(description: "For technical issues and bugs", to: technicalAgent)
    ]
)
```

## How Handoffs Work

When the LLM decides to hand off:

1. It calls the handoff tool with a reason
2. The ``Runner`` switches to the target agent
3. The conversation continues with the new agent's instructions
4. The new agent has access to the full conversation history

```swift
for try await event in runner.stream(triageAgent, input: "My payment failed") {
    switch event {
    case .handoff(let from, let to, let reason):
        print("Handed off from \(from) to \(to): \(reason)")
    case .textDelta(let text):
        print(text, terminator: "")
    default:
        break
    }
}
```

## Preventing Cycles

The ``Runner`` automatically prevents infinite handoff loops. If Agent A hands to Agent B, which tries to hand back to Agent A, an error is thrown.

## Advanced: Agents with Handoffs AND Tools

Agents can have both tools and handoffs:

```swift
let triageAgent = Agent<EmptyContext>(
    name: "Support",
    instructions: "Route users and look up their account.",
    tools: [AccountLookupTool()],
    handoffs: [
        Handoff(to: billingAgent),
        Handoff(to: technicalAgent)
    ]
)
```

The LLM decides whether to call a tool or hand off based on the user's request.
