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
        XCTAssertEqual(SculptLoop.extractCode(text),
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
        XCTAssertTrue(SculptLoop.extractCode(text).contains("const g"))
    }

    func testExtractCodeUnfenced() {
        let raw = "function buildModel(THREE) { return new THREE.Group(); }"
        XCTAssertEqual(SculptLoop.extractCode(raw), raw)
    }
}
