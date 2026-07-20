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

    /// UI state while the loop waits at the per-cycle gate (coach mode).
    struct CycleGateState {
        let snapshot: SculptCycleSnapshot
        /// Editable: what the coder will be told next cycle. Prefilled with
        /// the judge's critique; only a changed text is sent as an override.
        var critiqueDraft: String
        /// Editable via the spec sheet; only a changed text replaces the spec.
        var specDraft: String
        /// Which cycle's model carries forward. Prefilled with the pairwise
        /// gate's pick; the user can point it at any reviewed cycle.
        var selectedBase: Int
    }

    var phase: Phase = .idle
    var photoURL: URL?
    var photoImage: NSImage?
    var subjectImage: NSImage?
    var currentStage = ""
    var startedAt: Date?
    var cycles: [CycleRecord] = []
    /// Set after a run that produced a best model: fuels "Keep refining".
    var resumeSeed: SculptSeed?
    /// Non-nil while the loop waits for the user to approve the spec; bound
    /// to the spec editor.
    var pendingSpec: String?
    /// Non-nil while the loop waits at a cycle gate.
    var cycleGate: CycleGateState?
    /// "Use as base" clicked during autopilot; consumed at the next cycle
    /// boundary without pausing the loop.
    var pendingBaseOverride: Int?

    private var specContinuation: CheckedContinuation<String, Never>?
    private var cycleContinuation: CheckedContinuation<SculptCycleDecision, Never>?
    private var coachMode: () -> Bool = { false }
    /// Intent of the current run, kept so "Keep Refining" preserves it (a
    /// mid-run refine-spec call still needs it).
    private var runIntent: String?

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
             coderSeesRenders: Bool = true, intent: String? = nil,
             coachMode: @escaping () -> Bool = { false },
             seed: SculptSeed? = nil) {
        guard phase != .running else { return }
        reset()
        phase = .running
        photoURL = photo
        photoImage = NSImage(contentsOf: photo)
        startedAt = Date()
        currentStage = "starting"
        self.coachMode = coachMode
        runIntent = intent?.isEmpty == true ? nil : intent

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
                                          userIntent: runIntent,
                                          outDir: outDir)
                let loop = SculptLoop(config: config, harness: harness)
                let outcome = try await loop.run(photoPath: photo.path,
                                                 seed: seed,
                                                 gate: makeGate()) { [weak self] event in
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
    /// in-flight render or export JS finishes first. A loop parked at a human
    /// gate must be resumed first or the cancel would never be seen.
    func cancel() {
        currentStage = "cancelling after the current call..."
        if let cont = specContinuation {
            specContinuation = nil
            let draft = pendingSpec ?? ""
            pendingSpec = nil
            cont.resume(returning: draft)
        }
        if let cont = cycleContinuation {
            cycleContinuation = nil
            cycleGate = nil
            cont.resume(returning: SculptCycleDecision(action: .continueRun))
        }
        runTask?.cancel()
    }

    // MARK: - Human gates

    /// The loop's two pause points. Autopilot cycles never suspend: they just
    /// consume a pending "Use as base" click. Coach mode parks the loop on a
    /// continuation until the user decides.
    private func makeGate() -> SculptGate {
        SculptGate(
            approveSpec: { [weak self] draft in
                guard let self else { return draft }
                return await withCheckedContinuation { cont in
                    self.currentStage = "review the spec"
                    self.pendingSpec = draft
                    self.specContinuation = cont
                }
            },
            reviewCycle: { [weak self] snapshot in
                guard let self else { return SculptCycleDecision() }
                guard self.coachMode() else {
                    let forced = self.pendingBaseOverride
                    self.pendingBaseOverride = nil
                    return SculptCycleDecision(
                        forcedIncumbent: forced == snapshot.bestCycle ? nil : forced)
                }
                return await withCheckedContinuation { cont in
                    self.currentStage = "paused - your call"
                    self.cycleGate = CycleGateState(
                        snapshot: snapshot,
                        critiqueDraft: snapshot.review.critique,
                        specDraft: snapshot.spec,
                        selectedBase: self.pendingBaseOverride ?? snapshot.bestCycle)
                    self.pendingBaseOverride = nil
                    self.cycleContinuation = cont
                }
            })
    }

    /// The user approved (possibly edited) the spec: cycles start.
    func approveSpec() {
        guard let cont = specContinuation else { return }
        let spec = pendingSpec ?? ""
        specContinuation = nil
        pendingSpec = nil
        currentStage = "starting cycles"
        cont.resume(returning: spec)
    }

    /// The user decided at a cycle gate. Only fields they actually changed
    /// become overrides; untouched drafts defer to the loop.
    func resumeCycle(accept: Bool) {
        guard let gate = cycleGate, let cont = cycleContinuation else { return }
        cycleContinuation = nil
        cycleGate = nil
        let critique = gate.critiqueDraft == gate.snapshot.review.critique
            ? nil : gate.critiqueDraft
        let spec = gate.specDraft == gate.snapshot.spec ? nil : gate.specDraft
        let forced = gate.selectedBase == gate.snapshot.bestCycle
            ? nil : gate.selectedBase
        cont.resume(returning: SculptCycleDecision(
            action: accept ? .acceptNow : .continueRun,
            critique: critique, forcedIncumbent: forced, spec: spec))
    }

    /// "Use as base" during autopilot: no pause, applied at the next boundary.
    func overrideBase(_ cycle: Int) {
        if cycleGate != nil {
            cycleGate?.selectedBase = cycle
        } else {
            pendingBaseOverride = cycle
        }
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
            coderSeesRenders: coderSeesRenders, intent: runIntent,
            coachMode: coachMode, seed: resumeSeed)
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
        pendingSpec = nil
        cycleGate = nil
        pendingBaseOverride = nil
        specContinuation = nil
        cycleContinuation = nil
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
