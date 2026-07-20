import XCTest
@testable import MaquetteKit

final class SculptPromptsTests: XCTestCase {
    func testCodegenUserFirstCycleIsSpecOnly() {
        let text = SculptPrompts.codegenUser(spec: "{\"object\":\"case\"}",
                                             previousCode: nil,
                                             critique: nil, jsError: nil)
        XCTAssertTrue(text.hasPrefix("SPEC:"))
        XCTAssertFalse(text.contains("PREVIOUS CODE"))
        XCTAssertFalse(text.contains("BEST CODE"))
    }

    func testCodegenUserIncumbentFraming() {
        let text = SculptPrompts.codegenUser(
            spec: "{}", previousCode: "function buildModel(THREE) {}",
            critique: "lid too flat", jsError: nil,
            incumbentScore: 0.82,
            layerScores: ["formDetail": 0.85, "materialSurface": 0.8],
            rendersAttached: true)
        XCTAssertTrue(text.contains("BEST CODE SO FAR (reviewer score 0.82"))
        XCTAssertTrue(text.contains("formDetail 0.85"))
        XCTAssertTrue(text.contains("materialSurface 0.80"))
        XCTAssertTrue(text.contains("attached image"))
        XCTAssertTrue(text.contains("CRITIQUE:\nlid too flat"))
        XCTAssertFalse(text.contains("PREVIOUS CODE"))
        XCTAssertFalse(text.contains("discarded"))
    }

    func testCodegenUserRegressionNote() {
        let text = SculptPrompts.codegenUser(
            spec: "{}", previousCode: "code",
            critique: "seam misplaced", jsError: nil,
            incumbentScore: 0.7, regressed: true)
        XCTAssertTrue(text.contains("judged WORSE"))
        XCTAssertTrue(text.contains("discarded"))
    }

    func testSpecUserCarriesBrief() {
        let text = SculptPrompts.specUser(
            critique: nil, previousSpec: nil,
            brief: "the box opens; a pair of earbuds sits inside")
        XCTAssertTrue(text.contains("BUILD BRIEF"))
        XCTAssertTrue(text.contains("a pair of earbuds sits inside"))
        XCTAssertTrue(text.contains("authoritative"))
    }

    func testSpecUserOmitsBriefWhenEmpty() {
        XCTAssertFalse(SculptPrompts.specUser(critique: nil, previousSpec: nil,
                                              brief: "").contains("BUILD BRIEF"))
        XCTAssertFalse(SculptPrompts.specUser(critique: nil, previousSpec: nil)
            .contains("BUILD BRIEF"))
    }

    func testJudgePromptsReceiveSpec() {
        // The spec can extend beyond the photo (user intent: interiors, open
        // state); a judge scoring against the photo alone would punish the
        // correct model, so both judge stages must carry the spec.
        let spec = #"{"object":"ipod box, lid open"}"#
        XCTAssertTrue(SculptPrompts.reviewUser(spec: spec)
            .contains("SPEC:\n\(spec)"))
        XCTAssertTrue(SculptPrompts.pairwiseUser(spec: spec)
            .contains("SPEC:\n\(spec)"))
        XCTAssertTrue(SculptPrompts.reviewSystem.contains("never punish"))
        XCTAssertTrue(SculptPrompts.pairwiseSystem.contains("never count"))
    }

    func testCodegenUserCrashLaneHasNoIncumbentFraming() {
        // Crash retries iterate on the crashing code itself; the incumbent
        // framing (and its image) belongs only to the fresh-attempt lane.
        let text = SculptPrompts.codegenUser(
            spec: "{}", previousCode: "bad code",
            critique: "ignored", jsError: "x is not defined")
        XCTAssertTrue(text.contains("PREVIOUS CODE:\nbad code"))
        XCTAssertTrue(text.contains("YOUR CODE CRASHED"))
        XCTAssertFalse(text.contains("BEST CODE"))
        XCTAssertFalse(text.contains("CRITIQUE"))
    }
}
