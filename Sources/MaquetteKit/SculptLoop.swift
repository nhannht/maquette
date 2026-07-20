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
    public var outDir: URL

    public init(coder: ModelSlotConfig, vision: ModelSlotConfig,
                threshold: Double = 0.7, maxCycles: Int = 5,
                codeErrorRetries: Int = 2, outDir: URL) {
        self.coder = coder
        self.vision = vision
        self.threshold = threshold
        self.maxCycles = maxCycles
        self.codeErrorRetries = codeErrorRetries
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

public struct SculptOutcome {
    public let accepted: Bool
    public let finalScore: Double
    public let cyclesRun: Int
    public let finalFactory: String
    public let coderUsage: SlotUsage
    public let visionUsage: SlotUsage
}

public enum SculptEvent {
    case stage(String)
    case cycleStart(Int)
    case review(cycle: Int, ReviewResult)
}

public enum SculptLoopError: Error, CustomStringConvertible {
    case badReviewJSON(String)
    case noSpec(String)

    public var description: String {
        switch self {
        case .badReviewJSON(let detail): return "vision review was not valid JSON: \(detail)"
        case .noSpec(let detail): return "spec stage returned no JSON: \(detail)"
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

    public func run(photoPath: String,
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

        onEvent(.stage("analyze + spec (vision slot)"))
        var spec = try await makeSpec(subjectPNG: subjectPNG, critique: nil, previousSpec: nil)
        try write(spec, name: "spec-1.json")

        var code = ""
        var critique: String?
        var jsError: String?
        var lastReview: ReviewResult?
        var cyclesRun = 0

        for cycle in 1...config.maxCycles {
            cyclesRun = cycle
            onEvent(.cycleStart(cycle))
            let cycleDir = config.outDir.appendingPathComponent("cycle-\(cycle)")
            try fm.createDirectory(at: cycleDir, withIntermediateDirectories: true)

            // Codegen, with a bounded free retry lane for plain JS crashes.
            var renders: [(view: RenderView, png: Data)]?
            for attempt in 0...config.codeErrorRetries {
                onEvent(.stage("codegen (coder slot)\(attempt > 0 ? ", crash fix \(attempt)" : "")"))
                let result = try await config.coder.client.completeOnce(
                    model: config.coder.modelID,
                    messages: [
                        ChatMessage(role: .system, text: SculptPrompts.codegenSystem),
                        ChatMessage(role: .user, text: SculptPrompts.codegenUser(
                            spec: spec, previousCode: code.isEmpty ? nil : code,
                            critique: critique, jsError: jsError)),
                    ],
                    temperature: SculptPrompts.codegenTemperature,
                    maxTokens: SculptPrompts.codegenMaxTokens)
                coderUsage.add(result.usage)
                code = Self.extractCode(result.text)
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

            onEvent(.stage("review (vision slot)"))
            let review = try await makeReview(sheetPNG: sheet)
            lastReview = review
            let reviewJSON = try JSONSerialization.data(
                withJSONObject: ["overallScore": review.overallScore,
                                 "layerScores": review.layerScores ?? [:],
                                 "critique": review.critique,
                                 "action": review.action],
                options: [.prettyPrinted, .sortedKeys])
            try write(reviewJSON, name: "cycle-\(cycle)/review.json")
            onEvent(.review(cycle: cycle, review))

            if review.overallScore >= config.threshold || review.action == "stop"
                || review.action == "continue" {
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
            }
        }

        try write(code, name: "factory-final.js")
        let score = lastReview?.overallScore ?? 0
        return SculptOutcome(accepted: score >= config.threshold,
                             finalScore: score,
                             cyclesRun: cyclesRun,
                             finalFactory: code,
                             coderUsage: coderUsage,
                             visionUsage: visionUsage)
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
            maxTokens: SculptPrompts.specMaxTokens)
        visionUsage.add(result.usage)
        guard let json = Self.extractJSON(result.text) else {
            throw SculptLoopError.noSpec(String(result.text.prefix(300)))
        }
        return json
    }

    private func makeReview(sheetPNG: Data) async throws -> ReviewResult {
        let result = try await config.vision.client.completeOnce(
            model: config.vision.modelID,
            messages: [
                ChatMessage(role: .system, text: SculptPrompts.reviewSystem),
                ChatMessage(role: .user, content: [
                    .imagePNG(sheetPNG),
                    .text(SculptPrompts.reviewUser),
                ]),
            ],
            temperature: SculptPrompts.reviewTemperature,
            maxTokens: SculptPrompts.reviewMaxTokens)
        visionUsage.add(result.usage)
        guard let json = Self.extractJSON(result.text),
              let data = json.data(using: .utf8),
              let review = try? JSONDecoder().decode(ReviewResult.self, from: data) else {
            throw SculptLoopError.badReviewJSON(String(result.text.prefix(300)))
        }
        return review
    }

    // MARK: - Text extraction (LLMs love fences no matter what the prompt says)

    nonisolated static func extractJSON(_ text: String) -> String? {
        if let fenced = extractFenced(text, languages: ["json", ""]) {
            if fenced.first == "{" { return fenced }
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    nonisolated static func extractCode(_ text: String) -> String {
        if let fenced = extractFenced(text, languages: ["javascript", "js", ""]) {
            return fenced
        }
        return text
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
