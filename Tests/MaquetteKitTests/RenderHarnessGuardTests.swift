import XCTest
@testable import MaquetteKit

final class RenderHarnessGuardTests: XCTestCase {
    /// The exact trap from the blank-render runs (IMG3D-17): a 2D EllipseCurve
    /// fed to TubeGeometry yields NaN vertices and, before the guard, a blank
    /// render from every viewpoint with no JS error. It must now fail at load
    /// so the loop's free retry lane handles it.
    @MainActor
    func testNaNModelRejectedAtLoad() async throws {
        let harness = RenderHarness()
        defer { harness.shutdown() }
        try await harness.start()
        let nanFactory = """
        function buildModel(THREE) {
          const group = new THREE.Group();
          const curve = new THREE.EllipseCurve(0, 0, 0.5, 0.3, 0, 2 * Math.PI, false, 0);
          const geo = new THREE.TubeGeometry(curve, 32, 0.01, 8, true);
          group.add(new THREE.Mesh(geo, new THREE.MeshStandardMaterial()));
          return group;
        }
        """
        do {
            try await harness.loadFactory(nanFactory)
            XCTFail("expected a factory error for NaN geometry")
        } catch RenderHarnessError.factory(let detail) {
            XCTAssertTrue(detail.contains("not finite"), "unexpected detail: \(detail)")
        }
    }
}
