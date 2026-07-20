import SwiftUI
import AppKit
import SceneKit
import UniformTypeIdentifiers
import MaquetteKit

/// Drives one sculpt run for the UI: owns the harness + loop, translates the
/// loop's event stream into observable per-cycle records, and keeps the
/// exported artifacts. Runs land in Application Support (not tmp): the user
/// paid tokens for them, so the system must not garbage-collect them.
@MainActor
@Observable
final class SculptViewModel {
    enum Phase: Equatable {
        case idle
        case running
        case done
        case failed(String)
    }

    struct CycleRecord: Identifiable {
        let id: Int
        var stage: String
        var review: ReviewResult?
        var comparison: NSImage?
        /// Verdict of the head-to-head against the best model so far; nil for
        /// the first reviewable cycle (nothing to compare against yet).
        var pairwiseWon: Bool?
        var pairwiseReason: String?
        /// This cycle's own exported model - the user can overrule the judge
        /// and pick any cycle by eye.
        var usdzURL: URL?
    }

    static let threshold = 0.7
    static let maxCycles = 5

    var phase: Phase = .idle
    var photoURL: URL?
    var photoImage: NSImage?
    var subjectImage: NSImage?
    var currentStage = ""
    var startedAt: Date?
    var cycles: [CycleRecord] = []
    /// Set after a run that produced a best model: fuels "Keep refining".
    var resumeSeed: SculptSeed?

    var accepted = false
    var finalScore: Double = 0
    var bestCycle: Int?
    var usdzURL: URL?
    var glbURL: URL?
    var exportError: String?
    var usageSummary: String?
    var scene: SCNScene?
    var quickLookURL: URL?
    var outDir: URL?

    private var runTask: Task<Void, Never>?

    // MARK: - Running

    func run(photo: URL, coder: ModelSlotConfig, vision: ModelSlotConfig,
             coderSeesRenders: Bool = true, seed: SculptSeed? = nil) {
        guard phase != .running else { return }
        reset()
        phase = .running
        photoURL = photo
        photoImage = NSImage(contentsOf: photo)
        startedAt = Date()
        currentStage = "starting"

        runTask = Task { @MainActor in
            let harness = RenderHarness()
            defer { harness.shutdown() }
            do {
                let outDir = try Self.makeRunDir(photo: photo)
                self.outDir = outDir
                try await harness.start()
                let config = SculptConfig(coder: coder, vision: vision,
                                          threshold: Self.threshold,
                                          maxCycles: Self.maxCycles,
                                          coderSeesRenders: coderSeesRenders,
                                          outDir: outDir)
                let loop = SculptLoop(config: config, harness: harness)
                let outcome = try await loop.run(photoPath: photo.path,
                                                 seed: seed) { [weak self] event in
                    self?.apply(event)
                }
                finish(outcome)
            } catch is CancellationError {
                phase = .idle
            } catch let error as URLError where error.code == .cancelled {
                phase = .idle
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    /// Cancellation lands at the next network call (the expensive part);
    /// in-flight render or export JS finishes first.
    func cancel() {
        currentStage = "cancelling after the current call..."
        runTask?.cancel()
    }

    private func apply(_ event: SculptEvent) {
        switch event {
        case .stage(let name):
            currentStage = name
            if !cycles.isEmpty {
                cycles[cycles.count - 1].stage = name
            }
            // The spec stage follows subject lift, so the cutout (or its
            // absence) is settled by the time this fires.
            if name.hasPrefix("analyze") || name.hasPrefix("resuming"), let outDir {
                subjectImage = NSImage(contentsOf:
                    outDir.appendingPathComponent("subject.png"))
            }
            // The comparison sheet hits disk right before this stage: load it
            // now so the live view shows the model before the verdict arrives.
            if name.hasPrefix("export cycle"), let outDir,
               let last = cycles.indices.last {
                cycles[last].comparison = NSImage(contentsOf: outDir
                    .appendingPathComponent("cycle-\(cycles[last].id)/comparison.png"))
            }
        case .cycleStart(let cycle):
            cycles.append(CycleRecord(id: cycle, stage: "codegen"))
        case .review(let cycle, let review):
            guard let index = cycles.firstIndex(where: { $0.id == cycle }) else { return }
            cycles[index].review = review
            if let outDir {
                cycles[index].comparison = NSImage(contentsOf:
                    outDir.appendingPathComponent("cycle-\(cycle)/comparison.png"))
                let usdz = outDir.appendingPathComponent("cycle-\(cycle)/model.usdz")
                if FileManager.default.fileExists(atPath: usdz.path) {
                    cycles[index].usdzURL = usdz
                }
            }
        case .pairwise(let cycle, let challengerWon, let reason):
            guard let index = cycles.firstIndex(where: { $0.id == cycle }) else { return }
            cycles[index].pairwiseWon = challengerWon
            cycles[index].pairwiseReason = reason
        }
    }

    private func finish(_ outcome: SculptOutcome) {
        accepted = outcome.accepted
        finalScore = outcome.finalScore
        bestCycle = outcome.bestCycle
        glbURL = outcome.glbPath
        usdzURL = outcome.usdzPath
        exportError = outcome.exportError
        usageSummary = "coder \(outcome.coderUsage.calls) calls / "
            + "\(outcome.coderUsage.promptTokens + outcome.coderUsage.completionTokens) tokens, "
            + "vision \(outcome.visionUsage.calls) calls / "
            + "\(outcome.visionUsage.promptTokens + outcome.visionUsage.completionTokens) tokens"
        if let usdzURL {
            scene = try? SCNScene(url: usdzURL)
            scene?.background.contents = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        }
        if let review = outcome.bestReview, !outcome.finalFactory.isEmpty, let outDir {
            let sheetName = outcome.bestCycle == 0
                ? "seed-comparison.png"
                : "cycle-\(outcome.bestCycle ?? 0)/comparison.png"
            if let sheet = try? Data(contentsOf: outDir.appendingPathComponent(sheetName)) {
                resumeSeed = SculptSeed(spec: outcome.finalSpec,
                                        code: outcome.finalFactory,
                                        review: review, sheet: sheet)
            }
        }
        phase = .done
    }

    /// Resume from the best model: it becomes cycle 0's incumbent and new
    /// cycles must beat it through the pairwise gate.
    func keepRefining(coder: ModelSlotConfig, vision: ModelSlotConfig,
                      coderSeesRenders: Bool) {
        guard phase == .done, let photoURL, let resumeSeed else { return }
        run(photo: photoURL, coder: coder, vision: vision,
            coderSeesRenders: coderSeesRenders, seed: resumeSeed)
    }

    private func reset() {
        phase = .idle
        photoURL = nil
        photoImage = nil
        subjectImage = nil
        currentStage = ""
        startedAt = nil
        cycles = []
        resumeSeed = nil
        accepted = false
        finalScore = 0
        bestCycle = nil
        usdzURL = nil
        glbURL = nil
        exportError = nil
        usageSummary = nil
        scene = nil
        quickLookURL = nil
        outDir = nil
    }

    private static func makeRunDir(photo: URL) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("Maquette/runs", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(formatter.string(from: Date()))-"
            + photo.deletingPathExtension().lastPathComponent
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Result actions

    func newRun() {
        guard phase != .running else { return }
        reset()
    }

    func quickLook(_ url: URL? = nil) {
        quickLookURL = url ?? usdzURL
    }

    func saveUSDZ() {
        guard let usdzURL else { return }
        let panel = NSSavePanel()
        if let usdz = UTType(filenameExtension: "usdz") {
            panel.allowedContentTypes = [usdz]
        }
        panel.nameFieldStringValue = "model.usdz"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: usdzURL, to: dest)
        } catch {
            phase = .failed("save failed: \(error.localizedDescription)")
        }
    }

    func revealInFinder() {
        guard let outDir else { return }
        if let usdzURL {
            NSWorkspace.shared.activateFileViewerSelecting([usdzURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([outDir])
        }
    }
}
