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

    enum ResultTab: String, CaseIterable {
        case sheet = "Sheet"
        case model = "3D"
    }

    /// UI state while the loop waits between cycles for the user's go-ahead.
    struct CycleGateState {
        let snapshot: SculptCycleSnapshot
        /// The suggested next instruction for the coder (the judge's
        /// critique). Editable; only a changed text is sent as an override.
        var critiqueDraft: String
        /// Which cycle's model carries forward. Prefilled with the pairwise
        /// gate's pick; the user can point it at any reviewed cycle.
        var selectedBase: Int
    }

    var phase: Phase = .idle
    var photoURL: URL?
    var photoImage: NSImage?
    var subjectImage: NSImage?
    /// The run's reference images (primary first); fuels Keep Refining and
    /// the photo card thumbnails.
    var references: ReferenceSet?
    var referenceImages: [NSImage] = []
    var currentStage = ""
    var startedAt: Date?
    var cycles: [CycleRecord] = []
    /// Absolute cycle ceiling of the current session: grows by maxCycles on
    /// every Keep Refining round (numbering is continuous).
    var cycleCap = SculptViewModel.maxCycles
    /// Set after a run that produced a best model: fuels "Keep refining".
    var resumeSeed: SculptSeed?
    /// Non-nil while the loop waits for the user to confirm the suggested
    /// build brief; bound to the brief editor.
    var pendingBrief: String?
    /// Reference edits staged at the brief gate (primary first, parallel
    /// thumbnail array). Only a changed set is sent back to the loop.
    var pendingReferences: [ReferenceImage] = []
    var pendingReferenceThumbs: [NSImage] = []
    private var briefBaseReferences: ReferenceSet?
    /// Non-nil while the loop waits between cycles.
    var cycleGate: CycleGateState?
    /// The resumed run's previous-best comparison sheet, so gate 0 shows the
    /// model being refined instead of a spinner.
    var seedComparison: NSImage?
    /// The cycle whose artifacts the result column shows. nil = follow the
    /// run: latest reviewed cycle while running, the best cycle when done.
    var selectedCycle: Int?
    /// Which face of the viewed cycle the result column shows.
    var resultTab: ResultTab = .model

    private var briefContinuation: CheckedContinuation<BriefDecision, Never>?
    private var cycleContinuation: CheckedContinuation<SculptCycleDecision, Never>?
    private var autoContinue: () -> Bool = { false }

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

    func run(photos: [URL], coder: ModelSlotConfig, vision: ModelSlotConfig,
             coderSeesRenders: Bool = true,
             autoContinue: @escaping () -> Bool = { false }) {
        guard phase != .running, let first = photos.first else { return }
        reset()
        let set = ReferenceSet(
            primary: ReferenceImage(path: first.path),
            extras: photos.dropFirst().map { ReferenceImage(path: $0.path) })
        photoURL = first
        photoImage = NSImage(contentsOf: first)
        applyReferences(set)
        self.autoContinue = autoContinue
        begin(references: set, coder: coder, vision: vision,
              coderSeesRenders: coderSeesRenders, seed: nil)
    }

    private func applyReferences(_ set: ReferenceSet) {
        references = set
        referenceImages = set.all.compactMap { NSImage(contentsOfFile: $0.path) }
    }

    private func begin(references: ReferenceSet, coder: ModelSlotConfig,
                       vision: ModelSlotConfig, coderSeesRenders: Bool,
                       seed: SculptSeed?) {
        phase = .running
        startedAt = Date()
        currentStage = "starting"
        cycleCap = (seed?.cyclesRun ?? 0) + Self.maxCycles

        runTask = Task { @MainActor in
            let harness = RenderHarness()
            defer { harness.shutdown() }
            do {
                // A resumed session keeps growing the same directory so every
                // cycle of every round stays on disk, numbered continuously.
                let outDir: URL
                if let existing = self.outDir {
                    outDir = existing
                } else {
                    outDir = try Self.makeRunDir(
                        photo: URL(fileURLWithPath: references.primary.path))
                    self.outDir = outDir
                }
                try await harness.start()
                let config = SculptConfig(coder: coder, vision: vision,
                                          threshold: Self.threshold,
                                          maxCycles: Self.maxCycles,
                                          coderSeesRenders: coderSeesRenders,
                                          outDir: outDir)
                let loop = SculptLoop(config: config, harness: harness)
                let outcome = try await loop.run(
                    references: references,
                    seed: seed,
                    gate: makeGate(seeded: seed != nil)) { [weak self] event in
                    self?.apply(event)
                }
                finish(outcome)
            } catch is CancellationError {
                settle(afterCancelSeeded: seed != nil)
            } catch let error as URLError where error.code == .cancelled {
                settle(afterCancelSeeded: seed != nil)
            } catch {
                phase = .failed(String(describing: error))
            }
        }
    }

    /// A cancelled fresh run returns to the drop zone; a cancelled refining
    /// round falls back to the previous completed state - its cards, model,
    /// and Keep Refining button all still stand.
    private func settle(afterCancelSeeded seeded: Bool) {
        if seeded {
            cycles.removeAll { $0.review == nil }
            // The round is void: the viewer snaps back to the standing best
            // so the result column and the bottom bar agree again.
            if let bestCycle {
                select(cycle: bestCycle)
            }
            phase = .done
        } else {
            phase = .idle
        }
    }

    /// Cancellation lands at the next network call (the expensive part);
    /// in-flight render or export JS finishes first. A loop parked at a human
    /// gate must be resumed first or the cancel would never be seen.
    func cancel() {
        currentStage = "cancelling after the current call..."
        if let cont = briefContinuation {
            briefContinuation = nil
            let draft = pendingBrief ?? ""
            pendingBrief = nil
            pendingReferences = []
            pendingReferenceThumbs = []
            briefBaseReferences = nil
            cont.resume(returning: BriefDecision(brief: draft))
        }
        if let cont = cycleContinuation {
            cycleContinuation = nil
            cycleGate = nil
            cont.resume(returning: SculptCycleDecision(action: .continueRun))
        }
        runTask?.cancel()
    }

    // MARK: - Human gates

    /// The loop's pause points. The brief gate always waits: the user
    /// confirms or edits the suggested prompt before tokens are spent. The
    /// cycle gate waits whenever there is a next cycle to steer - including
    /// gate 0 of a resumed run, which is the whole point of Keep Refining.
    private func makeGate(seeded: Bool) -> SculptGate {
        SculptGate(
            approveBrief: { [weak self] draft in
                guard let self else { return BriefDecision(brief: draft.brief) }
                return await withCheckedContinuation { cont in
                    self.currentStage = "confirm the brief"
                    self.pendingBrief = draft.brief
                    self.pendingReferences = draft.references.all
                    self.pendingReferenceThumbs = draft.references.all.map {
                        NSImage(contentsOfFile: $0.path) ?? NSImage()
                    }
                    self.briefBaseReferences = draft.references
                    self.briefContinuation = cont
                }
            },
            reviewCycle: { [weak self] snapshot in
                guard let self else { return SculptCycleDecision() }
                guard !self.autoContinue() else { return SculptCycleDecision() }
                // No pause when there is nothing left to steer: the cycle cap,
                // or a fresh run the judge is about to accept (the result
                // screen takes over; Keep Refining reopens the wheel). A
                // seeded run never ends on the judge's score - the user
                // resumed past it deliberately, so only their word stops it.
                let lastCycle = snapshot.cycle >= self.cycleCap
                let freshRunEnding = !seeded
                    && (snapshot.bestScore >= Self.threshold
                        || snapshot.review.action == "stop"
                        || snapshot.review.action == "continue")
                guard !lastCycle, !freshRunEnding else {
                    return SculptCycleDecision()
                }
                return await withCheckedContinuation { cont in
                    self.currentStage = "waiting for you"
                    self.cycleGate = CycleGateState(
                        snapshot: snapshot,
                        critiqueDraft: snapshot.review.critique,
                        selectedBase: snapshot.bestCycle)
                    self.cycleContinuation = cont
                }
            })
    }

    /// The user confirmed (possibly edited) the brief: the spec compiles and
    /// cycles start.
    func approveBrief() {
        guard let cont = briefContinuation else { return }
        let brief = pendingBrief ?? ""
        // Only a genuinely changed set travels back to the loop (and only
        // then does the loop re-lift subjects).
        var changed: ReferenceSet?
        if let primary = pendingReferences.first {
            let staged = ReferenceSet(primary: primary,
                                      extras: Array(pendingReferences.dropFirst()))
            if staged != briefBaseReferences {
                changed = staged
                applyReferences(staged)
            }
        }
        briefContinuation = nil
        pendingBrief = nil
        pendingReferences = []
        pendingReferenceThumbs = []
        briefBaseReferences = nil
        currentStage = "building the spec"
        cont.resume(returning: BriefDecision(brief: brief, references: changed))
    }

    // MARK: - Brief-gate reference edits

    func addPendingReference(_ url: URL) {
        guard pendingReferences.count < 1 + ReferenceSet.maxExtras else { return }
        pendingReferences.append(ReferenceImage(path: url.path))
        pendingReferenceThumbs.append(NSImage(contentsOf: url) ?? NSImage())
    }

    /// The last reference cannot go: the loop needs at least one photo.
    func removePendingReference(at index: Int) {
        guard pendingReferences.count > 1,
              pendingReferences.indices.contains(index) else { return }
        pendingReferences.remove(at: index)
        pendingReferenceThumbs.remove(at: index)
    }

    func makePendingPrimary(_ index: Int) {
        guard index != 0, pendingReferences.indices.contains(index) else { return }
        pendingReferences.insert(pendingReferences.remove(at: index), at: 0)
        pendingReferenceThumbs.insert(pendingReferenceThumbs.remove(at: index), at: 0)
        // The primary slot has no label - the sheet names it REFERENCE.
        pendingReferences[0].label = nil
    }

    func setPendingLabel(_ index: Int, _ label: String) {
        guard pendingReferences.indices.contains(index) else { return }
        pendingReferences[index].label = label.isEmpty ? nil : label
    }

    /// The user decided between cycles. Only what they actually changed
    /// becomes an override; untouched drafts defer to the loop.
    func resumeCycle(accept: Bool) {
        guard let gate = cycleGate, let cont = cycleContinuation else { return }
        cycleContinuation = nil
        cycleGate = nil
        let critique = gate.critiqueDraft == gate.snapshot.review.critique
            ? nil : gate.critiqueDraft
        let forced = gate.selectedBase == gate.snapshot.bestCycle
            ? nil : gate.selectedBase
        cont.resume(returning: SculptCycleDecision(
            action: accept ? .acceptNow : .continueRun,
            critique: critique, forcedIncumbent: forced))
    }

    /// The human eye outranks the pairwise judge: while paused, any reviewed
    /// cycle can be picked as the base to carry forward.
    func overrideBase(_ cycle: Int) {
        cycleGate?.selectedBase = cycle
    }

    // MARK: - Cycle selection (result column viewer)

    /// Show this cycle in the result column: its model in the 3D tab when the
    /// cycle exported one, its comparison sheet otherwise.
    func select(cycle id: Int) {
        guard let record = cycles.first(where: { $0.id == id }) else { return }
        selectedCycle = id
        loadScene(from: record.usdzURL)
    }

    private func loadScene(from url: URL?) {
        guard let url, let loaded = try? SCNScene(url: url) else {
            scene = nil
            return
        }
        loaded.background.contents = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        scene = loaded
    }

    private func apply(_ event: SculptEvent) {
        switch event {
        case .stage(let name):
            currentStage = name
            if !cycles.isEmpty {
                cycles[cycles.count - 1].stage = name
            }
            // Recognize follows subject lift, so the cutout (or its absence)
            // is settled by the time any of these fire.
            if name.hasPrefix("recognize") || name.hasPrefix("analyze")
                || name.hasPrefix("resuming"), let outDir {
                subjectImage = NSImage(contentsOf:
                    outDir.appendingPathComponent("subject.png"))
            }
            // The loop writes the seed sheet right before this event fires.
            if name.hasPrefix("resuming"), let outDir {
                seedComparison = NSImage(contentsOf:
                    outDir.appendingPathComponent("seed-comparison.png"))
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
                    // Follow mode: with no explicit selection, the viewer
                    // tracks the freshest reviewed model.
                    if selectedCycle == nil {
                        loadScene(from: usdz)
                    }
                }
            }
        case .pairwise(let cycle, let challengerWon, let reason):
            guard let index = cycles.firstIndex(where: { $0.id == cycle }) else { return }
            cycles[index].pairwiseWon = challengerWon
            cycles[index].pairwiseReason = reason
        case .referencesChanged:
            // Subjects and every comparison sheet were rebuilt on disk against
            // the new reference set - reload what the cards show.
            guard let outDir else { return }
            subjectImage = NSImage(contentsOf:
                outDir.appendingPathComponent("subject.png"))
            seedComparison = NSImage(contentsOf:
                outDir.appendingPathComponent("seed-comparison.png"))
            for index in cycles.indices {
                let sheet = outDir.appendingPathComponent(
                    "cycle-\(cycles[index].id)/comparison.png")
                if FileManager.default.fileExists(atPath: sheet.path) {
                    cycles[index].comparison = NSImage(contentsOf: sheet)
                }
            }
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
        // The run's result is its best model: selection snaps to it, and the
        // user can re-click any card to inspect another cycle.
        selectedCycle = bestCycle
        if let usdzURL {
            loadScene(from: usdzURL)
        }
        if let review = outcome.bestReview, let best = outcome.bestCycle,
           !outcome.finalFactory.isEmpty, let outDir {
            let sheetName = "cycle-\(best)/comparison.png"
            if let sheet = try? Data(contentsOf: outDir.appendingPathComponent(sheetName)) {
                resumeSeed = SculptSeed(spec: outcome.finalSpec,
                                        code: outcome.finalFactory,
                                        review: review, sheet: sheet,
                                        bestCycle: best,
                                        cyclesRun: outcome.cyclesRun)
            }
        }
        phase = .done
    }

    /// Continue the same session: the best model stays the incumbent under
    /// its original cycle number, cards and artifacts keep accumulating, and
    /// new cycles must beat it through the pairwise gate.
    func keepRefining(coder: ModelSlotConfig, vision: ModelSlotConfig,
                      coderSeesRenders: Bool) {
        guard phase == .done, let references, let resumeSeed else { return }
        // Back to follow mode: the viewer tracks new challengers as they land.
        // The scene keeps the incumbent until the first review replaces it.
        selectedCycle = nil
        begin(references: references, coder: coder, vision: vision,
              coderSeesRenders: coderSeesRenders, seed: resumeSeed)
    }

    private func reset() {
        phase = .idle
        photoURL = nil
        photoImage = nil
        subjectImage = nil
        references = nil
        referenceImages = []
        pendingReferences = []
        pendingReferenceThumbs = []
        briefBaseReferences = nil
        currentStage = ""
        startedAt = nil
        cycles = []
        cycleCap = Self.maxCycles
        resumeSeed = nil
        pendingBrief = nil
        cycleGate = nil
        seedComparison = nil
        selectedCycle = nil
        resultTab = .model
        briefContinuation = nil
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
