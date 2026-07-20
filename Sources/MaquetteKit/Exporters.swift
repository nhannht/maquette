import Foundation

// Model export. Both formats come out of the same THREE.Group the loop just
// rendered, via the three.js exporter addons bundled beside sculpt.html, so the
// geometry Swift writes is the geometry the vision judge scored. Swift moves
// bytes and never rebuilds the model, which is why there is no second
// representation to keep in sync.

public enum ExportFormat: String, CaseIterable, Sendable {
    case glb, usdz

    /// Conventional artifact name written next to a run's other artifacts.
    public var fileName: String { "model.\(rawValue)" }
}

extension RenderHarness {
    /// Export the currently loaded factory model. Call `loadFactory` first:
    /// this exports whatever geometry the page currently holds.
    public func export(_ format: ExportFormat) async throws -> Data {
        let status = try await callAsyncJS(
            "return await window.maquette.exportModel('\(format.rawValue)');")
        let obj = try Self.check(status, wrap: RenderHarnessError.exportFailed)
        guard let base64 = obj["data"] as? String else {
            throw RenderHarnessError.exportFailed("page returned no data field")
        }
        guard let data = Data(base64Encoded: base64), !data.isEmpty else {
            throw RenderHarnessError.exportFailed(
                "undecodable or empty \(format.rawValue) payload (\(base64.count) base64 chars)")
        }
        return data
    }
}
