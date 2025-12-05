import XCTest
@testable import AgentSDK

final class MessageTests: XCTestCase {

    func testMessageCreation() {
        let message = Message(
            role: .user,
            content: "Hello"
        )

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello")
        XCTAssertNil(message.toolCalls)
        XCTAssertNil(message.toolCallId)
    }

    func testConvenienceInitializers() {
        let system = Message.system("System prompt")
        XCTAssertEqual(system.role, .system)
        XCTAssertEqual(system.content, "System prompt")

        let user = Message.user("User message")
        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.content, "User message")

        let assistant = Message.assistant("Assistant response")
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, "Assistant response")

        let tool = Message.tool(callId: "call_123", content: "Tool result")
        XCTAssertEqual(tool.role, .tool)
        XCTAssertEqual(tool.toolCallId, "call_123")
        XCTAssertEqual(tool.content, "Tool result")
    }

    func testToolCallDecoding() throws {
        let toolCall = ToolCall(
            id: "call_abc",
            name: "get_weather",
            arguments: #"{"city": "San Francisco"}"#
        )

        struct WeatherArgs: Codable {
            let city: String
        }

        let args = try toolCall.decodeArguments(WeatherArgs.self)
        XCTAssertEqual(args.city, "San Francisco")
    }

    func testToolResultCreation() throws {
        struct ResultValue: Codable {
            let temperature: Int
        }

        let result = try ToolResult.success(
            callId: "call_123",
            name: "get_weather",
            value: ResultValue(temperature: 72)
        )

        XCTAssertEqual(result.callId, "call_123")
        XCTAssertEqual(result.name, "get_weather")
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("72"))
    }

    func testToolResultError() {
        let result = ToolResult.error(
            callId: "call_123",
            name: "get_weather",
            message: "City not found"
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.content, "City not found")
    }
}
