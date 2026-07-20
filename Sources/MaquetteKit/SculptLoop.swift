import AppKit
import DepthCardKit

// The self-correction loop: subject lift -> spec -> [codegen -> render ->
// review] until the vision score clears the threshold or the cycle cap hits.
// Every cycle writes its artifacts (factory.js, renders, comparison sheet,
// review.json) under outDir so a human can audit what the models did.

public struct SculptConfig {
    public var coder: ModelSlotConfig
    public var vision: ModelSlotConfig
    public var threshold: Double
    public var maxCycles: Int
    public var codeErrorRetries: Int
    /// Attach the best cycle's comparison sheet to codegen prompts. Requires a
    /// multimodal coder (gemini, kimi); turn off for text-only coders like
    /// qwen3-coder, whose endpoint rejects image parts.
    public var coderSeesRenders: Bool
    public var outDir: URL

    public init(coder: ModelSlotConfig, vision: ModelSlotConfig,
                threshold: Double = 0.7, maxCycles: Int = 5,
                codeErrorRetries: Int = 2, coderSeesRenders: Bool = true,
                outDir: URL) {
        self.coder = coder
        self.vision = vision
        self.threshold = threshold
        self.maxCycles = maxCycles
        self.codeErrorRetries = codeErrorRetries
        self.coderSeesRenders = coderSeesRenders
        self.outDir = outDir
    }
}

public struct ReviewResult: Decodable {
    public let overallScore: Double
    public let layerScores: [String: Double]?
    public let critique: String
    public let action: String
}

public struct SlotUsage {
    public var promptTokens = 0
    public var completionTokens = 0
    public var calls = 0

    mutating func add(_ usage: ChatUsage?) {
        calls += 1
        promptTokens += usage?.promptTokens ?? 0
        completionTokens += usage?.completionTokens ?? 0
    }
}

/// Starting incumbent for a resumed run: the previous run's best model
/// becomes cycle 0 and every new cycle must beat it through the pairwise
/// gate. Lets the user keep refining past an accepted score.
public struct SculptSeed {
    public let spec: String
    public let code: String
    public let review: ReviewResult
    public let sheet: Data

    public init(spec: String, code: String, review: ReviewResult, sheet: Data) {
        self.spec = spec
        self.code = code
        self.review = review
        self.sheet = sheet
    }
}

public struct SculptOutcome {
    public let accepted: Bool
    public let finalScore: Double
    public let cyclesRun: Int
    /// Which cycle produced the exported model: nil when none was reviewable,
    /// 0 when a resumed run's seed was never beaten.
    public let bestCycle: Int?
    public let finalFactory: String
    /// The best model's review and the spec in force at the end - everything
    /// a follow-up run needs to seed itself.
    public let bestReview: ReviewResult?
    public let finalSpec: String
    public let coderUsage: SlotUsage
    public let visionUsage: SlotUsage
    /// Written artifacts, nil when that format did not make it out.
    public let glbPath: URL?
    public let usdzPath: URL?
    /// Why export produced less than both files. A failed export never fails
    /// the run, but it is never silent either.
    public let exportError: String?
}

public enum SculptEvent {
    case stage(String)
    case cycleStart(Int)
    case review(cycle: Int, ReviewResult)
    case pairwise(cycle: Int, challengerWon: Bool, reason: String)
}

/// Verdict of the head-to-head gate between the incumbent and a challenger.
public struct PairwiseVerdict: Decodable {
    public let winner: String
    public let reason: String
}

public enum SculptLoopError: Error, CustomStringConvertible {
    case badReviewJSON(String)
    case badPairwiseJSON(String)
    case noSpec(String)
    case noCode(String)

    public var description: String {
        switch self {
        case .badReviewJSON(let detail): return "vision review was not valid JSON: \(detail)"
        case .badPairwiseJSON(let detail):
            return "pairwise verdict was not valid JSON: \(detail)"
        case .noSpec(let detail): return "spec stage returned no JSON: \(detail)"
        case .noCode(let detail):
            return "coder response contains no code (no fence, no buildModel): \(detail)"
        }
    }
}

@MainActor
public final class SculptLoop {
    private let config: SculptConfig
    private let harness: RenderHarness
    private var coderUsage = SlotUsage()
    private var visionUsage = SlotUsage()

    public init(config: SculptConfig, harness: RenderHarness) {
        self.config = config
        self.harness = harness
    }

    public func run(photoPath: String, seed: SculptSeed? = nil,
                    onEvent: (SculptEvent) -> Void) async throws -> SculptOutcome {
        let fm = FileManager.default
        try fm.createDirectory(at: config.outDir, withIntermediateDirectories: true)
        let photo = try loadCGImage(photoPath)

        // Subject lift is best-effort: a busy background hurts the vision
        // comparison but a failed mask must not kill the run.
        onEvent(.stage("subject lift"))
        var subject = photo
        do {
            let mask = try subjectMask(for: photo)
            let cutoutPath = config.outDir.appendingPathComponent("subject.png").path
            try saveCutout(photo: photo, mask: mask, to: cutoutPath)
            subject = try loadCGImage(cutoutPath)
        } catch {
            onEvent(.stage("subject lift failed (\(error)), using raw photo"))
        }
        let subjectPNG = try Self.pngData(subject)

        // `code` is transient: it is the previous-code hint fed to the next
        // codegen call, and refine-spec deliberately clears it to force a fresh
        // build. `best` is durable: the incumbent model, replaceable only by a
        // challenger that wins the pairwise gate. Keeping them separate is what
        // stops a late regression from discarding a better earlier model.
        var code = ""
        var critique: String?
        var jsError: String?
        var best: (cycle: Int, code: String, review: ReviewResult, sheet: Data)?
        var lastRegressed = false
        var freshBuild = true
        var cyclesRun = 0

        var spec: String
        if let seed {
            // Resumed run: the seed is the incumbent, no spec call needed.
            spec = seed.spec
            best = (cycle: 0, code: seed.code, review: seed.review, sheet: seed.sheet)
            freshBuild = false
            try write(seed.sheet, name: "seed-comparison.png")
            onEvent(.stage("resuming from previous best (score "
                + String(format: "%.2f", seed.review.overallScore) + ")"))
        } else {
            onEvent(.stage("analyze + spec (vision slot)"))
            spec = try await makeSpec(subjectPNG: subjectPNG, critique: nil, previousSpec: nil)
        }
        try write(spec, name: "spec-1.json")

        for cycle in 1...config.maxCycles {
            cyclesRun = cycle
            onEvent(.cycleStart(cycle))
            let cycleDir = config.outDir.appendingPathComponent("cycle-\(cycle)")
            try fm.createDirectory(at: cycleDir, withIntermediateDirectories: true)

            // Each cycle iterates on the incumbent, never on whatever the last
            // cycle left behind - a discarded regression must not become the
            // next baseline. A fresh build (cycle 1, or right after a spec
            // refine) starts from the spec alone.
            if let best, !freshBuild {
                code = best.code
                critique = best.review.critique
                jsError = nil
            }
            freshBuild = false

            // Codegen, with a bounded free retry lane for plain JS crashes.
            var renders: [(view: RenderView, png: Data)]?
            for attempt in 0...config.codeErrorRetries {
                onEvent(.stage("codegen (coder slot)\(attempt > 0 ? ", crash fix \(attempt)" : "")"))
                let inheritsIncumbent = jsError == nil && !code.isEmpty
                    && code == best?.code
                var userContent: [ChatContent] = []
                if inheritsIncumbent && config.coderSeesRenders, let sheet = best?.sheet {
                    userContent.append(.imagePNG(sheet))
                }
                userContent.append(.text(SculptPrompts.codegenUser(
                    spec: spec, previousCode: code.isEmpty ? nil : code,
                    critique: critique, jsError: jsError,
                    incumbentScore: inheritsIncumbent ? best?.review.overallScore : nil,
                    layerScores: inheritsIncumbent ? best?.review.layerScores : nil,
                    rendersAttached: inheritsIncumbent && config.coderSeesRenders,
                    regressed: inheritsIncumbent && lastRegressed)))
                // Truncation and code-less responses are attempt failures like
                // JS crashes: retry within the lane instead of killing a run
                // that has already paid for earlier cycles. Only the last
                // attempt's failure propagates.
                do {
                    let result = try await config.coder.client.completeOnce(
                        model: config.coder.modelID,
                        messages: [
                            ChatMessage(role: .system, text: SculptPrompts.codegenSystem),
                            ChatMessage(role: .user, content: userContent),
                        ],
                        temperature: SculptPrompts.codegenTemperature,
                        maxTokens: Self.codegenBudget(attempt: attempt),
                        reasoningMaxTokens: config.coder.reasoning
                            ? SculptPrompts.codegenReasoningMaxTokens : nil)
                    coderUsage.add(result.usage)
                    code = try Self.extractCode(result.text)
                } catch let error where Self.isRetryableCodegenFailure(error) {
                    guard attempt < config.codeErrorRetries else { throw error }
                    onEvent(.stage("codegen failed (\(error)), retrying"))
                    try write("\(error)", name: "cycle-\(cycle)/codegen-error-\(attempt).txt")
                    continue
                }
                try write(code, name: "cycle-\(cycle)/factory\(attempt > 0 ? "-fix\(attempt)" : "").js")

                onEvent(.stage("render"))
                do {
                    renders = try await harness.renderAll(factory: code)
                    jsError = nil
                    break
                } catch RenderHarnessError.factory(let detail) {
                    jsError = detail
                    try write(detail, name: "cycle-\(cycle)/js-error\(attempt > 0 ? "-\(attempt)" : "").txt")
                }
            }
            guard let renders else {
                // Crashed through every retry: spend the cycle, keep the error
                // as the critique so the next cycle's codegen sees it.
                critique = "Your code kept crashing. Last error: \(jsError ?? "unknown")"
                continue
            }
            for (view, png) in renders {
                try write(png, name: "cycle-\(cycle)/render-\(view.rawValue).png")
            }

            let sheet = try ComparisonSheet.compose(reference: subject, renders: renders)
            try write(sheet, name: "cycle-\(cycle)/comparison.png")

            // Every reviewable cycle's model is exported, not just the gate's
            // pick: the judge is a proxy for the user's eye, and when they
            // disagree the user is ground truth - they pick from cycle-N/.
            // The page still holds this cycle's model after renderAll, so this
            // is local and free. A failed export never fails the cycle.
            onEvent(.stage("export cycle model"))
            for format in ExportFormat.allCases {
                do {
                    let data = try await harness.export(format)
                    try write(data, name: "cycle-\(cycle)/\(format.fileName)")
                } catch {
                    onEvent(.stage("cycle export failed (\(format.rawValue)): \(error)"))
                }
            }

            onEvent(.stage("review (vision slot)"))
            let review = try await makeReview(sheetPNG: sheet, spec: spec)
            let reviewJSON = try JSONSerialization.data(
                withJSONObject: ["overallScore": review.overallScore,
                                 "layerScores": review.layerScores ?? [:],
                                 "critique": review.critique,
                                 "action": review.action],
                options: [.prettyPrinted, .sortedKeys])
            try write(reviewJSON, name: "cycle-\(cycle)/review.json")
            onEvent(.review(cycle: cycle, review))

            // Pairwise gate: absolute scores are too noisy to rank two models,
            // so a challenger replaces the incumbent only by beating it
            // head-to-head. The kept model never regresses in the judge's eyes.
            if let incumbent = best {
                onEvent(.stage("pairwise vs best (vision slot)"))
                let (challengerWon, reason) = try await makePairwise(
                    incumbentSheet: incumbent.sheet, challengerSheet: sheet,
                    spec: spec)
                let pairwiseJSON = try JSONSerialization.data(
                    withJSONObject: ["challengerWon": challengerWon, "reason": reason],
                    options: [.prettyPrinted, .sortedKeys])
                try write(pairwiseJSON, name: "cycle-\(cycle)/pairwise.json")
                onEvent(.pairwise(cycle: cycle, challengerWon: challengerWon,
                                  reason: reason))
                if challengerWon {
                    best = (cycle, code, review, sheet)
                    lastRegressed = false
                } else {
                    lastRegressed = true
                }
            } else {
                best = (cycle, code, review, sheet)
            }

            if (best?.review.overallScore ?? 0) >= config.threshold
                || review.action == "stop" || review.action == "continue" {
                break
            }
            critique = review.critique
            jsError = nil
            if review.action == "refine-spec" {
                onEvent(.stage("refine spec (vision slot)"))
                spec = try await makeSpec(subjectPNG: subjectPNG,
                                          critique: review.critique, previousSpec: spec)
                try write(spec, name: "spec-\(cycle + 1).json")
                code = ""  // spec changed; force a fresh build instead of a patch
                critique = nil
                freshBuild = true
            }
        }

        // The run's result is its best model, not whatever the last cycle left
        // behind: the loop can regress, and shipping a model worse than one it
        // already built would throw away work the user paid for.
        let finalCode = best?.code ?? ""
        try write(finalCode, name: "factory-final.js")

        let export = await exportFinal(code: finalCode, onEvent: onEvent)

        let score = best?.review.overallScore ?? 0
        return SculptOutcome(accepted: score >= config.threshold,
                             finalScore: score,
                             cyclesRun: cyclesRun,
                             bestCycle: best?.cycle,
                             finalFactory: finalCode,
                             bestReview: best?.review,
                             finalSpec: spec,
                             coderUsage: coderUsage,
                             visionUsage: visionUsage,
                             glbPath: export.glb,
                             usdzPath: export.usdz,
                             exportError: export.error)
    }

    // MARK: - Export

    /// Write the final geometry as GLB and USDZ. Reloads the factory first: if
    /// the last cycle crashed through every retry, the page still holds an
    /// earlier cycle's model, and exporting that would ship geometry no one
    /// scored. Export never throws - a run that produced a good model and a bad
    /// file is still a run worth reporting.
    private func exportFinal(code: String, onEvent: (SculptEvent) -> Void)
        async -> (glb: URL?, usdz: URL?, error: String?) {
        guard !code.isEmpty else {
            let reason = "no cycle produced a reviewable model"
            onEvent(.stage("export skipped: \(reason)"))
            return (nil, nil, reason)
        }
        onEvent(.stage("export"))
        var paths: [ExportFormat: URL] = [:]
        var failure: String?
        do {
            try await harness.loadFactory(code)
            for format in ExportFormat.allCases {
                let data = try await harness.export(format)
                try write(data, name: format.fileName)
                paths[format] = config.outDir.appendingPathComponent(format.fileName)
            }
        } catch {
            failure = String(describing: error)
            onEvent(.stage("export failed: \(failure!)"))
        }
        return (paths[.glb], paths[.usdz], failure)
    }

    // MARK: - LLM stages

    private func makeSpec(subjectPNG: Data, critique: String?,
                          previousSpec: String?) async throws -> String {
        let result = try await config.vision.client.completeOnce(
            model: config.vision.modelID,
            messages: [
                ChatMessage(role: .system, text: SculptPrompts.specSystem),
                ChatMessage(role: .user, content: [
                    .imagePNG(subjectPNG),
                    .text(SculptPrompts.specUser(critique: critique, previousSpec: previousSpec)),
                ]),
            ],
            temperature: SculptPrompts.specTemperature,
            maxTokens: SculptPrompts.specMaxTokens,
            reasoningMaxTokens: config.vision.reasoning
                ? SculptPrompts.specReasoningMaxTokens : nil)
        visionUsage.add(result.usage)
        guard let json = Self.extractJSON(result.text) else {
            throw SculptLoopError.noSpec(String(result.text.prefix(300)))
        }
        return json
    }

    private func makeReview(sheetPNG: Data, spec: String) async throws -> ReviewResult {
        let result = try await config.vision.client.completeOnce(
            model: config.vision.modelID,
            messages: [
                ChatMessage(role: .system, text: SculptPrompts.reviewSystem),
                ChatMessage(role: .user, content: [
                    .imagePNG(sheetPNG),
                    .text(SculptPrompts.reviewUser(spec: spec)),
                ]),
            ],
            temperature: SculptPrompts.reviewTemperature,
            maxTokens: SculptPrompts.reviewMaxTokens,
            reasoningMaxTokens: config.vision.reasoning
                ? SculptPrompts.reviewReasoningMaxTokens : nil)
        visionUsage.add(result.usage)
        guard let json = Self.extractJSON(result.text),
              let data = json.data(using: .utf8),
              let review = try? JSONDecoder().decode(ReviewResult.self, from: data) else {
            throw SculptLoopError.badReviewJSON(String(result.text.prefix(300)))
        }
        return review
    }

    /// Head-to-head verdict between the incumbent's sheet and the challenger's.
    /// A/B order is randomized per call to neutralize the judge's position bias.
    private func makePairwise(incumbentSheet: Data, challengerSheet: Data,
                              spec: String)
        async throws -> (challengerWon: Bool, reason: String) {
        let incumbentFirst = Bool.random()
        let result = try await config.vision.client.completeOnce(
            model: config.vision.modelID,
            messages: [
                ChatMessage(role: .system, text: SculptPrompts.pairwiseSystem),
                ChatMessage(role: .user, content: [
                    .imagePNG(incumbentFirst ? incumbentSheet : challengerSheet),
                    .imagePNG(incumbentFirst ? challengerSheet : incumbentSheet),
                    .text(SculptPrompts.pairwiseUser(spec: spec)),
                ]),
            ],
            temperature: SculptPrompts.pairwiseTemperature,
            maxTokens: SculptPrompts.pairwiseMaxTokens,
            reasoningMaxTokens: config.vision.reasoning
                ? SculptPrompts.pairwiseReasoningMaxTokens : nil)
        visionUsage.add(result.usage)
        let verdict = try Self.parsePairwise(result.text)
        let firstWon = verdict.winner == "A"
        return (incumbentFirst ? !firstWon : firstWon, verdict.reason)
    }

    /// Completion budget for a codegen attempt, doubling per retry. Some
    /// reasoning models ignore the advisory reasoning cap outright and eat
    /// the entire budget thinking (kimi-k2.7-code consumed 16384 of 16384);
    /// when the failure is "hit max_tokens", more tokens IS the remedy -
    /// retrying the same budget can only starve identically.
    nonisolated static func codegenBudget(attempt: Int) -> Int {
        min(SculptPrompts.codegenMaxTokens << attempt, 65536)
    }

    /// Attempt-scoped codegen failures: the model hit its token budget before
    /// emitting code, or answered with prose instead of code. Both are
    /// transient sampling outcomes worth another attempt; everything else
    /// (auth, network, bad request) aborts the run.
    nonisolated static func isRetryableCodegenFailure(_ error: Error) -> Bool {
        if case ChatClientError.truncated = error { return true }
        if case SculptLoopError.noCode = error { return true }
        return false
    }

    // MARK: - Text extraction (LLMs love fences no matter what the prompt says)

    nonisolated static func parsePairwise(_ text: String) throws -> PairwiseVerdict {
        guard let json = extractJSON(text), let data = json.data(using: .utf8),
              let verdict = try? JSONDecoder().decode(PairwiseVerdict.self, from: data),
              verdict.winner == "A" || verdict.winner == "B" else {
            throw SculptLoopError.badPairwiseJSON(String(text.prefix(300)))
        }
        return verdict
    }

    nonisolated static func extractJSON(_ text: String) -> String? {
        if let fenced = extractFenced(text, languages: ["json", ""]) {
            if fenced.first == "{" { return fenced }
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    nonisolated static func extractCode(_ text: String) throws -> String {
        if let fenced = extractFenced(text, languages: ["javascript", "js", ""]) {
            return fenced
        }
        // No fence is fine only when the body is plainly the code itself.
        // Anything else (reasoning prose, apologies, half sentences) is a
        // transport failure to surface, never something for new Function.
        if text.contains("function buildModel") { return text }
        throw SculptLoopError.noCode(String(text.prefix(300)))
    }

    /// Content of the largest fenced block matching one of the language tags.
    private nonisolated static func extractFenced(_ text: String, languages: [String]) -> String? {
        var best: String?
        var inBlock = false
        var blockLang = ""
        var current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inBlock {
                    let body = current.joined(separator: "\n")
                    if languages.contains(blockLang), body.count > (best?.count ?? 0) {
                        best = body
                    }
                    inBlock = false
                    current = []
                } else {
                    inBlock = true
                    blockLang = String(trimmed.dropFirst(3)).lowercased()
                }
                continue
            }
            if inBlock { current.append(line) }
        }
        return best
    }

    // MARK: - Artifacts

    private func write(_ content: String, name: String) throws {
        try write(Data(content.utf8), name: name)
    }

    private func write(_ data: Data, name: String) throws {
        try data.write(to: config.outDir.appendingPathComponent(name))
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ComparisonSheetError.encodeFailed
        }
        return png
    }
}
