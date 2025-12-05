import XCTest
@testable import AgentSDK

final class AgentTests: XCTestCase {

    func testAgentCreation() {
        let agent = Agent<EmptyContext>(
            name: "TestAgent",
            instructions: "You are a test agent."
        )

        XCTAssertEqual(agent.name, "TestAgent")
        XCTAssertEqual(agent.instructions, "You are a test agent.")
        XCTAssertNil(agent.model)
        XCTAssertTrue(agent.tools.isEmpty)
        XCTAssertTrue(agent.handoffs.isEmpty)
    }

    func testAgentWithModel() {
        let agent = Agent<EmptyContext>(
            name: "TestAgent",
            instructions: "Test",
            model: "claude-3-haiku-20240307"
        )

        XCTAssertEqual(agent.model, "claude-3-haiku-20240307")
    }

    func testAgentFluentAPI() {
        let baseAgent = Agent<EmptyContext>(
            name: "TestAgent",
            instructions: "Test"
        )

        let withModel = baseAgent.using(model: "claude-3-opus-20240229")

        XCTAssertEqual(withModel.model, "claude-3-opus-20240229")
        XCTAssertEqual(withModel.name, baseAgent.name)
    }

    func testAnyAgentTypeErasure() {
        let agent = Agent<EmptyContext>(
            name: "TypedAgent",
            instructions: "Test instructions"
        )

        let anyAgent = AnyAgent(agent)

        XCTAssertEqual(anyAgent.name, "TypedAgent")
        XCTAssertEqual(anyAgent.instructions, "Test instructions")
    }
}
