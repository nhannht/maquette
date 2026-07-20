import XCTest
@testable import MaquetteKit

@MainActor
final class ExportersTests: XCTestCase {
    func testFileNames() {
        XCTAssertEqual(ExportFormat.glb.fileName, "model.glb")
        XCTAssertEqual(ExportFormat.usdz.fileName, "model.usdz")
        XCTAssertEqual(ExportFormat.allCases.count, 2)
    }

    func testCheckReturnsPayload() throws {
        let status = #"{"ok": true, "data": "QUJD"}"#
        let obj = try RenderHarness.check(status, wrap: RenderHarnessError.exportFailed)
        XCTAssertEqual(obj["data"] as? String, "QUJD")
        XCTAssertEqual(Data(base64Encoded: obj["data"] as! String), Data("ABC".utf8))
    }

    func testCheckPropagatesPageError() {
        let status = #"{"ok": false, "error": "no model loaded"}"#
        XCTAssertThrowsError(
            try RenderHarness.check(status, wrap: RenderHarnessError.exportFailed)
        ) { error in
            XCTAssertEqual((error as? RenderHarnessError)?.description,
                           "export failed: no model loaded")
        }
    }

    func testCheckRejectsNonStatusResult() {
        // A promise that resolved to something other than our JSON contract.
        XCTAssertThrowsError(
            try RenderHarness.check(42, wrap: RenderHarnessError.exportFailed))
        XCTAssertThrowsError(
            try RenderHarness.check(nil, wrap: RenderHarnessError.exportFailed))
        XCTAssertThrowsError(
            try RenderHarness.check("not json", wrap: RenderHarnessError.exportFailed))
    }

    func testEmptyBase64DecodesToEmptyData() {
        // export() treats this as a failure rather than writing a 0-byte model.
        XCTAssertEqual(Data(base64Encoded: ""), Data())
    }
}
