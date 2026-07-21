import AppKit
import MaquetteKit

// Headless driver for the sculpt loop. Three commands:
//   set-key <coder|vision>          key from stdin -> Keychain, never argv/files
//   render-test [--out DIR]         free WebGL smoke test, no tokens spent
//   sculpt <photo> --out DIR ...    full loop against configured endpoints

let defaultEndpoint = "https://openrouter.ai/api/v1"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func usage() -> Never {
    print("""
    usage:
      maquette-cli set-key <coder|vision>
      maquette-cli render-test [--out DIR]
      maquette-cli export <factory.js> [--out DIR]
      maquette-cli sculpt <photo> [photo2 photo3 photo4] --out DIR
          [--coder-model ID] [--vision-model ID]
          [--coder-endpoint URL] [--vision-endpoint URL]
          [--cycles N] [--threshold X] [--coder-text-only]
          [--coder-no-reasoning] [--vision-no-reasoning]
          [--intent TEXT] [--spec-file PATH]

    Extra photos are further views of the SAME object (first photo = primary
    view); they sharpen the brief, the spec, and the judge's read.
    --coder-text-only: do not attach reference or render images to codegen
    prompts; required for text-only coder models (e.g. qwen3-coder), which
    reject image input.
    --coder-no-reasoning / --vision-no-reasoning: do not send the reasoning
    token budget for that slot (for endpoints that reject the field).
    --intent: the build brief (skips the recognize call); may go beyond what
    the photo shows (interior, open state, hidden side) - judged authoritative.
    --spec-file: use this spec JSON verbatim and skip recognize + spec calls.
    Keys are optional for keyless local endpoints (Ollama, LM Studio).

    Keys come from the Keychain (accounts apikey.coder / apikey.vision, set via
    set-key). If apikey.vision is absent the coder key is used for both slots.
    Default endpoint for both slots: \(defaultEndpoint)
    """)
    exit(2)
}

struct Flags {
    static let booleanFlags: Set<String> =
        ["coder-text-only", "coder-no-reasoning", "vision-no-reasoning"]

    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ args: [String]) {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if Self.booleanFlags.contains(name) {
                    options[name] = "true"
                    index += 1
                    continue
                }
                guard index + 1 < args.count else { fail("missing value for \(arg)") }
                options[name] = args[index + 1]
                index += 2
            } else {
                positional.append(arg)
                index += 1
            }
        }
    }
}

func setKey(slot: String) {
    guard slot == "coder" || slot == "vision" else { usage() }
    print("Paste the API key for the \(slot) slot, then press Enter:")
    guard let line = readLine(strippingNewline: true)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
        fail("no key read from stdin")
    }
    do {
        try Keychain.set(line, account: "apikey.\(slot)")
        print("Stored in Keychain as apikey.\(slot) (service com.nhannht.maquette).")
    } catch {
        fail("keychain write failed: \(error)")
    }
}

@MainActor
func makeHarness() async throws -> RenderHarness {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let harness = RenderHarness()
    try await harness.start()
    return harness
}

let cubeFactory = """
function buildModel(THREE) {
  const group = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.BoxGeometry(1, 0.6, 0.7),
    new THREE.MeshStandardMaterial({ color: 0x8b5a2b, roughness: 0.7 }));
  group.add(body);
  const lid = new THREE.Mesh(
    new THREE.CylinderGeometry(0.35, 0.35, 1, 32, 1, false, 0, Math.PI),
    new THREE.MeshStandardMaterial({ color: 0xa0522d, roughness: 0.6 }));
  lid.rotation.z = Math.PI / 2;
  lid.position.y = 0.3;
  group.add(lid);
  const ring = new THREE.Mesh(
    new THREE.TorusGeometry(0.08, 0.02, 12, 32),
    new THREE.MeshStandardMaterial({ color: 0xd4af37, metalness: 0.9, roughness: 0.25 }));
  ring.position.set(0, 0.1, 0.36);
  group.add(ring);
  return group;
}
"""

@MainActor
func renderTest(outDir: URL) async throws {
    let harness = try await makeHarness()
    defer { harness.shutdown() }
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let renders = try await harness.renderAll(factory: cubeFactory)
    for (view, png) in renders {
        let path = outDir.appendingPathComponent("render-test-\(view.rawValue).png")
        try png.write(to: path)
        print("\(path.path)  \(png.count) bytes")
    }
    // The chest fixture carries three distinct materials (matte body, lighter
    // lid, metallic ring), so exporting it here proves material fidelity
    // end to end without spending a token.
    for format in ExportFormat.allCases {
        let data = try await harness.export(format)
        let path = outDir.appendingPathComponent(format.fileName)
        try data.write(to: path)
        print("\(path.path)  \(data.count) bytes")
    }
    print("render-test OK: \(renders.count) viewpoints captured, "
          + "\(ExportFormat.allCases.count) formats exported")
}

/// Export any saved factory (e.g. a non-winning cycle's factory.js from an old
/// run) to GLB + USDZ. Local and free: no model slots, no tokens.
@MainActor
func exportFactory(flags: Flags) async throws {
    guard let factoryPath = flags.positional.dropFirst().first else { usage() }
    let code = try String(contentsOfFile: factoryPath, encoding: .utf8)
    let outDir = URL(fileURLWithPath: flags.options["out"] ?? ".")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let harness = try await makeHarness()
    defer { harness.shutdown() }
    try await harness.loadFactory(code)
    for format in ExportFormat.allCases {
        let data = try await harness.export(format)
        let path = outDir.appendingPathComponent(format.fileName)
        try data.write(to: path)
        print("\(path.path)  \(data.count) bytes")
    }
}

@MainActor
func sculpt(flags: Flags) async throws {
    let photos = Array(flags.positional.dropFirst())
    guard let primaryPath = photos.first else { usage() }
    guard photos.count <= 1 + ReferenceSet.maxExtras else {
        fail("at most \(1 + ReferenceSet.maxExtras) photos (1 primary + "
             + "\(ReferenceSet.maxExtras) extra views)")
    }
    let references = ReferenceSet(
        primary: ReferenceImage(path: primaryPath),
        extras: photos.dropFirst().map { ReferenceImage(path: $0) })
    guard let outPath = flags.options["out"] else { fail("--out DIR is required") }
    // Missing keys are fine for keyless local endpoints (Ollama, LM Studio);
    // a hosted endpoint without a key fails loudly at the first call.
    let coderKey = Keychain.get(account: "apikey.coder") ?? ""
    let visionKey = Keychain.get(account: "apikey.vision") ?? coderKey

    guard let coderModel = flags.options["coder-model"],
          let visionModel = flags.options["vision-model"] else {
        fail("--coder-model and --vision-model are required")
    }
    guard let coderEndpoint = URL(string: flags.options["coder-endpoint"] ?? defaultEndpoint),
          let visionEndpoint = URL(string: flags.options["vision-endpoint"] ?? defaultEndpoint) else {
        fail("bad endpoint URL")
    }

    let config = SculptConfig(
        coder: ModelSlotConfig(endpoint: coderEndpoint, modelID: coderModel,
                               apiKey: coderKey,
                               reasoning: flags.options["coder-no-reasoning"] == nil),
        vision: ModelSlotConfig(endpoint: visionEndpoint, modelID: visionModel,
                                apiKey: visionKey,
                                reasoning: flags.options["vision-no-reasoning"] == nil),
        threshold: Double(flags.options["threshold"] ?? "0.7") ?? 0.7,
        maxCycles: Int(flags.options["cycles"] ?? "5") ?? 5,
        coderSeesRenders: flags.options["coder-text-only"] == nil,
        userIntent: flags.options["intent"],
        presetSpec: flags.options["spec-file"].map { path in
            guard let spec = try? String(contentsOfFile: path, encoding: .utf8) else {
                fail("cannot read --spec-file \(path)")
            }
            return spec
        },
        outDir: URL(fileURLWithPath: outPath))

    print("coder:  \(coderModel) @ \(coderEndpoint.absoluteString)")
    print("vision: \(visionModel) @ \(visionEndpoint.absoluteString)")
    print("threshold \(config.threshold), max cycles \(config.maxCycles)")

    let harness = try await makeHarness()
    defer { harness.shutdown() }
    let loop = SculptLoop(config: config, harness: harness)
    let outcome = try await loop.run(references: references) { event in
        switch event {
        case .stage(let name):
            print("  - \(name)")
        case .cycleStart(let cycle):
            print("cycle \(cycle)/\(config.maxCycles)")
        case .review(_, let review):
            let layers = (review.layerScores ?? [:])
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(String(format: "%.2f", $0.value))" }
                .joined(separator: " ")
            print("  score \(String(format: "%.2f", review.overallScore)) " +
                  "action=\(review.action) [\(layers)]")
            print("  critique: \(review.critique.prefix(400))")
        case .pairwise(_, let challengerWon, let reason):
            let verdict = challengerWon
                ? "challenger wins, becomes best"
                : "best model defends, attempt discarded"
            print("  pairwise: \(verdict) - \(reason.prefix(200))")
        case .referencesChanged:
            print("  - references changed; comparison sheets rebuilt")
        }
    }

    print("""

    RESULT: \(outcome.accepted ? "ACCEPTED" : "NOT ACCEPTED") \
    score \(String(format: "%.2f", outcome.finalScore)) \
    from cycle \(outcome.bestCycle.map(String.init) ?? "-") of \(outcome.cyclesRun) run
    coder:  \(outcome.coderUsage.calls) calls, \(outcome.coderUsage.promptTokens) prompt + \
    \(outcome.coderUsage.completionTokens) completion tokens
    vision: \(outcome.visionUsage.calls) calls, \(outcome.visionUsage.promptTokens) prompt + \
    \(outcome.visionUsage.completionTokens) completion tokens
    glb:    \(outcome.glbPath?.path ?? "none")
    usdz:   \(outcome.usdzPath?.path ?? "none")
    artifacts: \(config.outDir.path)
    """)
    if let exportError = outcome.exportError {
        print("export problem: \(exportError)")
    }
}

let flags = Flags(Array(CommandLine.arguments.dropFirst()))
guard let command = flags.positional.first else { usage() }

switch command {
case "set-key":
    guard flags.positional.count == 2 else { usage() }
    setKey(slot: flags.positional[1])
    exit(0)
case "render-test", "sculpt", "export":
    Task { @MainActor in
        do {
            if command == "render-test" {
                let out = URL(fileURLWithPath: flags.options["out"] ?? "render-test-out")
                try await renderTest(outDir: out)
            } else if command == "export" {
                try await exportFactory(flags: flags)
            } else {
                try await sculpt(flags: flags)
            }
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
    RunLoop.main.run()
default:
    usage()
}
