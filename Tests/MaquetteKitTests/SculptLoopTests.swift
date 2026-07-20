import XCTest
@testable import MaquetteKit

final class SculptLoopTests: XCTestCase {
    func testExtractJSONFromFence() {
        let text = """
        Here is the spec:
        ```json
        {"object": "chest"}
        ```
        """
        XCTAssertEqual(SculptLoop.extractJSON(text), #"{"object": "chest"}"#)
    }

    func testExtractJSONBare() {
        let text = #"noise {"overallScore": 0.5, "critique": "x"} trailing"#
        XCTAssertEqual(SculptLoop.extractJSON(text),
                       #"{"overallScore": 0.5, "critique": "x"}"#)
    }

    func testExtractJSONMissing() {
        XCTAssertNil(SculptLoop.extractJSON("no braces here"))
    }

    func testExtractCodeFromFence() {
        let text = """
        Sure!
        ```javascript
        function buildModel(THREE) { return new THREE.Group(); }
        ```
        Done.
        """
        XCTAssertEqual(try SculptLoop.extractCode(text),
                       "function buildModel(THREE) { return new THREE.Group(); }")
    }

    func testExtractCodePicksLargestFence() {
        let text = """
        ```js
        // small
        ```
        ```js
        function buildModel(THREE) {
          const g = new THREE.Group();
          return g;
        }
        ```
        """
        XCTAssertTrue(try SculptLoop.extractCode(text).contains("const g"))
    }

    func testExtractCodeUnfenced() {
        let raw = "function buildModel(THREE) { return new THREE.Group(); }"
        XCTAssertEqual(try SculptLoop.extractCode(raw), raw)
    }

    func testCodegenBudgetEscalates() {
        XCTAssertEqual(SculptLoop.codegenBudget(attempt: 0), 16384)
        XCTAssertEqual(SculptLoop.codegenBudget(attempt: 1), 32768)
        XCTAssertEqual(SculptLoop.codegenBudget(attempt: 2), 65536)
        XCTAssertEqual(SculptLoop.codegenBudget(attempt: 3), 65536)
    }

    func testRetryableCodegenFailures() {
        XCTAssertTrue(SculptLoop.isRetryableCodegenFailure(
            ChatClientError.truncated("reasoning ate the budget")))
        XCTAssertTrue(SculptLoop.isRetryableCodegenFailure(
            SculptLoopError.noCode("prose")))
        XCTAssertFalse(SculptLoop.isRetryableCodegenFailure(
            SculptLoopError.badReviewJSON("x")))
        XCTAssertFalse(SculptLoop.isRetryableCodegenFailure(URLError(.timedOut)))
    }

    func testAutopilotGateIsTheZeroValue() async throws {
        // Autopilot must be indistinguishable from the pre-gate loop: the
        // brief passes through untouched and every decision defers to the loop.
        let brief = await SculptGate.autopilot.approveBrief("a closed white box")
        XCTAssertEqual(brief, "a closed white box")

        let review = try JSONDecoder().decode(ReviewResult.self, from: Data(
            #"{"overallScore":0.5,"critique":"x","action":"refine-code"}"#.utf8))
        let decision = await SculptGate.autopilot.reviewCycle(SculptCycleSnapshot(
            cycle: 1, review: review, challengerWon: nil, bestCycle: 1,
            bestScore: 0.5, spec: #"{"object":"box"}"#, availableCycles: [1]))
        guard case .auto = decision.action else {
            return XCTFail("autopilot must not steer the loop")
        }
        XCTAssertNil(decision.critique)
        XCTAssertNil(decision.forcedIncumbent)
        XCTAssertNil(decision.spec)
    }

    func testParsePairwiseVerdict() throws {
        let verdict = try SculptLoop.parsePairwise(
            #"Sure! {"winner": "B", "reason": "better silhouette"}"#)
        XCTAssertEqual(verdict.winner, "B")
        XCTAssertEqual(verdict.reason, "better silhouette")
    }

    func testParsePairwiseRejectsBadWinner() {
        XCTAssertThrowsError(try SculptLoop.parsePairwise(
            #"{"winner": "C", "reason": "x"}"#)) { error in
            guard case SculptLoopError.badPairwiseJSON = error else {
                return XCTFail("expected .badPairwiseJSON, got \(error)")
            }
        }
        XCTAssertThrowsError(try SculptLoop.parsePairwise("no json at all"))
    }

    func testExtractCodeProseThrows() {
        // Leaked reasoning prose, as observed in the IMG3D-12 gemini run:
        // no fence, no buildModel. Must never reach new Function.
        let prose = """
        *   Front is `angle = Math.PI / 2`.
            *   Wait, the groove should look like an indentation.
        """
        XCTAssertThrowsError(try SculptLoop.extractCode(prose)) { error in
            guard case SculptLoopError.noCode = error else {
                return XCTFail("expected .noCode, got \(error)")
            }
        }
    }
}
