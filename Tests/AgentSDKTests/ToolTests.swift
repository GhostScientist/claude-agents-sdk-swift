import XCTest
@testable import AgentSDK

final class ToolTests: XCTestCase {

    func testFunctionToolCreation() async throws {
        let tool = FunctionTool(
            name: "test_tool",
            description: "A test tool",
            inputSchema: .object(
                properties: [
                    "input": .string("Test input")
                ],
                required: ["input"]
            )
        ) { _, _ in
            return "result"
        }

        XCTAssertEqual(tool.name, "test_tool")
        XCTAssertEqual(tool.description, "A test tool")

        let result = try await tool.execute(
            arguments: #"{"input": "test"}"#,
            context: EmptyContext()
        )

        XCTAssertEqual(result, "result")
    }

    func testToolDefinitionFromTool() {
        let tool = FunctionTool(
            name: "my_tool",
            description: "My tool description",
            inputSchema: .object(
                properties: ["param": .string()],
                required: ["param"]
            )
        ) { _, _ in "" }

        let definition = ToolDefinition(from: tool)

        XCTAssertEqual(definition.name, "my_tool")
        XCTAssertEqual(definition.description, "My tool description")
    }

    func testToolsBuilder() {
        let tool1 = FunctionTool(
            name: "tool1",
            description: "Tool 1",
            inputSchema: .object(properties: [:])
        ) { _, _ in "" }

        let tool2 = FunctionTool(
            name: "tool2",
            description: "Tool 2",
            inputSchema: .object(properties: [:])
        ) { _, _ in "" }

        let agent = Agent<EmptyContext>(
            name: "Test",
            instructions: "Test"
        ) {
            tool1
            tool2
        }

        XCTAssertEqual(agent.tools.count, 2)
        XCTAssertEqual(agent.tools[0].name, "tool1")
        XCTAssertEqual(agent.tools[1].name, "tool2")
    }
}
