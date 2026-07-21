import XCTest
@testable import MaquetteKit

@MainActor
final class ComparisonSheetTests: XCTestCase {
    private func solidImage(width: Int = 64, height: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func renderPNGs() throws -> [(view: RenderView, png: Data)] {
        let png = try SculptLoop.pngData(solidImage())
        return RenderView.allCases.map { ($0, png) }
    }

    func testSingleReferenceKeepsSheetDimensions() throws {
        let sheet = try ComparisonSheet.compose(
            references: [(image: solidImage(), label: nil)],
            renders: renderPNGs())
        let rep = NSBitmapImageRep(data: sheet)
        XCTAssertEqual(rep?.pixelsWide, 1344)
        XCTAssertEqual(rep?.pixelsHigh, 768)
    }

    func testFourReferencesKeepSheetDimensions() throws {
        // Extra views land in the strip; downstream sizing assumptions on the
        // sheet must not move.
        let references: [(image: CGImage, label: String?)] = [
            (solidImage(), nil),
            (solidImage(), "back"),
            (solidImage(), nil),
            (solidImage(), "open lid"),
        ]
        let sheet = try ComparisonSheet.compose(references: references,
                                                renders: renderPNGs())
        let rep = NSBitmapImageRep(data: sheet)
        XCTAssertEqual(rep?.pixelsWide, 1344)
        XCTAssertEqual(rep?.pixelsHigh, 768)
    }

    func testExtrasBeyondCapStillCompose() throws {
        // Defensive: the sheet caps the strip at ReferenceSet.maxExtras even
        // if a caller hands it more.
        let references = (0..<6).map { (image: solidImage(), label: "v\($0)" as String?) }
        let sheet = try ComparisonSheet.compose(references: references,
                                                renders: renderPNGs())
        let rep = NSBitmapImageRep(data: sheet)
        XCTAssertEqual(rep?.pixelsWide, 1344)
        XCTAssertEqual(rep?.pixelsHigh, 768)
    }

    func testNoReferenceThrows() throws {
        XCTAssertThrowsError(try ComparisonSheet.compose(references: [],
                                                         renders: renderPNGs())) { error in
            guard case ComparisonSheetError.noReference = error else {
                return XCTFail("expected .noReference, got \(error)")
            }
        }
    }
}
