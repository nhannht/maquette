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
