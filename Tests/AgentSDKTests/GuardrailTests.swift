import XCTest
@testable import AgentSDK

final class GuardrailTests: XCTestCase {

    func testMaxLengthGuardrailPasses() async throws {
        let guardrail = MaxLengthGuardrail(maxLength: 100)
        let result = try await guardrail.validate("Short message", context: EmptyContext())

        XCTAssertEqual(result, .passed)
    }

    func testMaxLengthGuardrailBlocks() async throws {
        let guardrail = MaxLengthGuardrail(maxLength: 10, truncate: false)
        let result = try await guardrail.validate("This is a very long message", context: EmptyContext())

        if case .blocked(let reason) = result {
            XCTAssertTrue(reason.contains("10"))
        } else {
            XCTFail("Expected blocked result")
        }
    }

    func testMaxLengthGuardrailTruncates() async throws {
        let guardrail = MaxLengthGuardrail(maxLength: 10, truncate: true)
        let result = try await guardrail.validate("This is a very long message", context: EmptyContext())

        if case .modified(let newContent, _) = result {
            XCTAssertEqual(newContent.count, 10)
            XCTAssertEqual(newContent, "This is a ")
        } else {
            XCTFail("Expected modified result")
        }
    }

    func testBlockPatternGuardrail() async throws {
        let guardrail = BlockPatternGuardrail(patterns: ["password", "secret"])

        let passResult = try await guardrail.validate("Hello world", context: EmptyContext())
        XCTAssertEqual(passResult, .passed)

        let blockResult = try await guardrail.validate("My password is 123", context: EmptyContext())
        if case .blocked = blockResult {
            // Expected
        } else {
            XCTFail("Expected blocked result")
        }
    }

    func testClosureGuardrail() async throws {
        let guardrail = inputGuardrail(name: "TestGuardrail") { input, _ in
            if input.contains("blocked") {
                return .blocked(reason: "Contains blocked word")
            }
            return .passed
        }

        let passResult = try await guardrail.validate("Hello", context: EmptyContext())
        XCTAssertEqual(passResult, .passed)

        let blockResult = try await guardrail.validate("This is blocked", context: EmptyContext())
        if case .blocked = blockResult {
            // Expected
        } else {
            XCTFail("Expected blocked result")
        }
    }

    func testGuardrailResultCanProceed() {
        XCTAssertTrue(GuardrailResult.passed.canProceed)
        XCTAssertTrue(GuardrailResult.modified(newContent: "new", reason: "").canProceed)
        XCTAssertFalse(GuardrailResult.blocked(reason: "").canProceed)
    }
}

// Make GuardrailResult Equatable for testing
extension GuardrailResult: Equatable {
    public static func == (lhs: GuardrailResult, rhs: GuardrailResult) -> Bool {
        switch (lhs, rhs) {
        case (.passed, .passed):
            return true
        case (.modified(let l1, let l2), .modified(let r1, let r2)):
            return l1 == r1 && l2 == r2
        case (.blocked(let l), .blocked(let r)):
            return l == r
        default:
            return false
        }
    }
}
