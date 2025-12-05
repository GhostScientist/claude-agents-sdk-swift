# Creating Tools

Extend your agent's capabilities with custom tools.

## Overview

Tools allow agents to perform actions beyond text generation—fetching data, making calculations, calling APIs, and more. The LLM decides when to use tools based on the user's request.

## Using the @Tool Macro

The simplest way to create a tool is with the `@Tool` macro:

```swift
import AgentSDK

@Tool("Get the current weather for a city")
struct WeatherTool {
    func execute(city: String, units: String = "celsius") async throws -> WeatherResult {
        // Fetch weather from an API
        let temp = try await fetchTemperature(city: city, units: units)
        return WeatherResult(temperature: temp, conditions: "Sunny")
    }
}

@ToolInput
struct WeatherResult: Codable {
    let temperature: Double
    let conditions: String
}
```

The macro automatically:
- Generates the tool name from the struct name (`weather`)
- Creates a JSON Schema from the `execute` parameters
- Handles argument parsing and result encoding

## Using FunctionTool

For inline tool definitions, use ``FunctionTool``:

```swift
let calculatorTool = FunctionTool(
    name: "calculate",
    description: "Evaluate a mathematical expression",
    inputSchema: .object(
        properties: [
            "expression": .string("The math expression to evaluate")
        ],
        required: ["expression"]
    )
) { arguments, context in
    struct Input: Codable { let expression: String }
    let input = try JSONDecoder().decode(Input.self, from: Data(arguments.utf8))

    // Evaluate the expression (simplified)
    let result = try evaluate(input.expression)
    return "Result: \(result)"
}
```

## Implementing the Tool Protocol

For complex tools with dependencies:

```swift
struct DatabaseSearchTool: Tool {
    let name = "search_database"
    let description = "Search the product database"

    let database: ProductDatabase

    var inputSchema: JSONSchema {
        .object(
            properties: [
                "query": .string("Search query"),
                "limit": .integer("Maximum results")
            ],
            required: ["query"]
        )
    }

    func execute(arguments: String, context: any AgentContext) async throws -> String {
        struct Input: Codable {
            let query: String
            let limit: Int?
        }

        let input = try JSONDecoder().decode(Input.self, from: Data(arguments.utf8))
        let results = try await database.search(input.query, limit: input.limit ?? 10)

        return results.map { $0.description }.joined(separator: "\n")
    }
}
```

## Adding Tools to Agents

Pass tools when creating an agent:

```swift
let agent = Agent<EmptyContext>(
    name: "Assistant",
    instructions: "Help users with weather and calculations.",
    tools: [
        WeatherTool(),
        calculatorTool
    ]
)
```

## Best Practices

1. **Write clear descriptions** - Help the LLM understand when to use each tool
2. **Define precise schemas** - Reduce argument parsing errors
3. **Return helpful results** - Include enough context for the LLM to formulate a response
4. **Handle errors gracefully** - Return informative error messages
