import AppKit
import WebKit

// Offscreen WKWebView that runs the bundled three.js page (sculpt.html) and
// snapshots LLM-generated factory code from fixed review viewpoints. Lives in
// an ordered-back borderless window far offscreen: WebGL needs a window-backed
// layer to composite, and this never steals focus or appears on screen.

public enum RenderView: String, CaseIterable, Sendable {
    case front, threeQuarter, side, top
}

public enum RenderHarnessError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case javascript(String)
    case factory(String)
    case snapshotFailed(String)
    case timeout(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name): return "bundled resource missing: \(name)"
        case .javascript(let detail): return "page error: \(detail)"
        case .factory(let detail): return "factory code failed: \(detail)"
        case .snapshotFailed(let detail): return "snapshot failed: \(detail)"
        case .timeout(let detail): return "timeout: \(detail)"
        }
    }
}

/// Serves sculpt.html and the vendored three.js builds from Bundle.module.
/// A custom scheme sidesteps every file:// module-import restriction WebKit has.
final class MaquetteSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "maquette"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let name = url.lastPathComponent
        guard let fileURL = Bundle.module.url(forResource: name, withExtension: nil,
                                              subdirectory: "Resources"),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(RenderHarnessError.resourceMissing(name))
            return
        }
        let mime = name.hasSuffix(".html") ? "text/html" : "text/javascript"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime,
                                                      "Access-Control-Allow-Origin": "*",
                                                      "Content-Length": String(data.count)])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
public final class RenderHarness {
    public static let size = CGSize(width: 768, height: 768)

    private let webView: WKWebView
    private let window: NSWindow

    public init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MaquetteSchemeHandler(),
                                   forURLScheme: MaquetteSchemeHandler.scheme)
        webView = WKWebView(frame: CGRect(origin: .zero, size: Self.size),
                            configuration: config)
        window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000),
                                              size: Self.size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.isReleasedWhenClosed = false
    }

    public func start(timeout: Duration = .seconds(10)) async throws {
        window.orderBack(nil)
        webView.load(URLRequest(url: URL(string: "maquette://app/sculpt.html")!))
        let clock = ContinuousClock()
        let started = clock.now
        while clock.now - started < timeout {
            let ready = try? await evalJS("window.maquette ? window.maquette.ready() : false")
            if (ready as? Bool) == true || (ready as? Int) == 1 { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw RenderHarnessError.timeout("sculpt.html never became ready")
    }

    public func shutdown() {
        window.orderOut(nil)
    }

    /// Evaluate LLM factory code. Throws .factory with the JS error text so the
    /// loop can hand it back to the coder slot as a compile-error retry.
    public func loadFactory(_ code: String) async throws {
        let encoded = String(data: try JSONEncoder().encode(code), encoding: .utf8)!
        let result = try await evalJS("window.maquette.load(\(encoded))")
        try Self.check(result, wrap: RenderHarnessError.factory)
    }

    public func snapshot(_ view: RenderView) async throws -> Data {
        let result = try await evalJS("window.maquette.view('\(view.rawValue)')")
        try Self.check(result, wrap: RenderHarnessError.javascript)
        // Let the freshly rendered WebGL frame reach the window server compositor.
        try await Task.sleep(for: .milliseconds(80))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: Self.size)
        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: config) { image, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: RenderHarnessError.snapshotFailed(
                        error?.localizedDescription ?? "no image"))
                }
            }
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw RenderHarnessError.snapshotFailed("PNG encode failed")
        }
        return png
    }

    /// Load factory code and capture every review viewpoint, in order.
    public func renderAll(factory: String) async throws -> [(view: RenderView, png: Data)] {
        try await loadFactory(factory)
        var out: [(RenderView, Data)] = []
        for view in RenderView.allCases {
            out.append((view, try await snapshot(view)))
        }
        return out
    }

    // MARK: - Plumbing

    private func evalJS(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: result)
                }
            }
        }
    }

    private static func check(_ result: Any?, wrap: (String) -> RenderHarnessError) throws {
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = obj["ok"] as? Bool else {
            throw wrap("page returned no status: \(String(describing: result).prefix(200))")
        }
        if !ok {
            throw wrap(obj["error"] as? String ?? "unknown page error")
        }
    }
}
