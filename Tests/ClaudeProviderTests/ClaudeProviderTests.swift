import XCTest
@testable import ClaudeProvider
@testable import AgentSDK

final class ClaudeProviderTests: XCTestCase {

    func testClaudeModelProperties() {
        let sonnet = ClaudeModel.claude35Sonnet

        XCTAssertEqual(sonnet.rawValue, "claude-3-5-sonnet-20241022")
        XCTAssertEqual(sonnet.displayName, "Claude 3.5 Sonnet")
        XCTAssertEqual(sonnet.maxContextTokens, 200_000)
    }

    func testClaudeProviderInitialization() {
        let provider = ClaudeProvider(apiKey: "test-key")

        XCTAssertEqual(provider.apiKey, "test-key")
        XCTAssertEqual(provider.defaultModel, ClaudeModel.claude35Sonnet.rawValue)
    }

    func testClaudeProviderWithCustomModel() {
        let provider = ClaudeProvider(
            apiKey: "test-key",
            model: .claude3Haiku
        )

        XCTAssertEqual(provider.defaultModel, ClaudeModel.claude3Haiku.rawValue)
    }
}
