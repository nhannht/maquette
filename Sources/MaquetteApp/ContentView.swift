import SwiftUI
import SceneKit
import QuickLook
import UniformTypeIdentifiers
import MaquetteKit

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings
    @State private var vm = SculptViewModel()

    private var coderConfig: ModelSlotConfig? { settings.config(for: .coder) }
    private var visionConfig: ModelSlotConfig? { settings.config(for: .vision) }
    private var configured: Bool { coderConfig != nil && visionConfig != nil }

    var body: some View {
        Group {
            if vm.phase == .idle {
                dropZone
            } else {
                runView
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .quickLookPreview($vm.quickLookURL)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !configured { configureBanner }
        }
    }

    // MARK: - Starting a run

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard vm.phase != .running else { return false }
        guard let url = urls.first(where: {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
        }) else { return false }
        start(url)
        return true
    }

    private func openPhotoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a photo of a single object"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start(url)
    }

    private func start(_ url: URL) {
        guard let coder = coderConfig, let vision = visionConfig else {
            openSettings()
            return
        }
        vm.run(photo: url, coder: coder, vision: vision)
    }

    // MARK: - Idle

    private var dropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "scale.3d")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Drop a photo")
                .font(.title2)
            Text("A coder LLM writes procedural geometry, a built-in renderer previews " +
                 "it, a vision model scores it against your photo, and the loop repeats " +
                 "until it looks right. Then GLB + USDZ export.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Open Photo...") { openPhotoPanel() }
                .keyboardShortcut("o")
                .disabled(!configured)
            Text("Up to \(SculptViewModel.maxCycles) cycles, accept at score " +
                 "\(Self.score(SculptViewModel.threshold)). \(slotLine)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var slotLine: String {
        guard let coder = coderConfig, let vision = visionConfig else {
            return "Configure both model slots to start."
        }
        return coder.modelID == vision.modelID
            ? "Model: \(coder.modelID)"
            : "Coder: \(coder.modelID), vision: \(vision.modelID)"
    }

    private var configureBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text("Both model slots need an endpoint, model ID, and API key before " +
                 "a run can start.")
                .font(.callout)
            Spacer()
            Button("Configure...") { openSettings() }
        }
        .padding(10)
        .background(.yellow.opacity(0.2))
    }

    // MARK: - Run (running / done / failed)

    private var runView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                cycleColumn
                    .frame(width: 320)
                Divider()
                resultColumn
            }
            Divider()
            bottomBar
        }
    }

    private var cycleColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                card(title: "Photo") {
                    HStack(alignment: .top, spacing: 8) {
                        thumbnail(vm.photoImage)
                        if vm.subjectImage != nil {
                            thumbnail(vm.subjectImage)
                        }
                    }
                    if vm.subjectImage != nil {
                        Text("subject lifted for comparison")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(vm.cycles) { cycle in
                    cycleCard(cycle)
                }
                if vm.phase == .running {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(vm.currentStage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                }
            }
            .padding(12)
        }
    }

    private func cycleCard(_ cycle: SculptViewModel.CycleRecord) -> some View {
        card(title: "Cycle \(cycle.id)") {
            if let review = cycle.review {
                HStack(spacing: 8) {
                    Text(Self.score(review.overallScore))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(
                            review.overallScore >= SculptViewModel.threshold
                                ? .green : .orange)
                    Text(review.action)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    if cycle.id == vm.bestCycle {
                        Text("best")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                    }
                }
                Text(review.critique)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                if let won = cycle.pairwiseWon {
                    Text(won ? "beat the previous best" : "discarded - previous best kept")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(won ? .green : .orange)
                        .help(cycle.pairwiseReason ?? "")
                }
                thumbnail(cycle.comparison, maxHeight: 90)
            } else {
                HStack(spacing: 8) {
                    if vm.phase == .running {
                        ProgressView().controlSize(.small)
                    }
                    Text(cycle.stage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func card(title: String,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func thumbnail(_ image: NSImage?, maxHeight: CGFloat = 110) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var resultColumn: some View {
        Group {
            if let scene = vm.scene {
                SceneView(scene: scene,
                          options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else if case .failed(let message) = vm.phase {
                VStack(spacing: 12) {
                    Image(systemName: "xmark.octagon")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Drop another photo to retry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.phase == .running {
                VStack(spacing: 12) {
                    if let latest = vm.cycles.last(where: { $0.comparison != nil })?.comparison {
                        Image(nsImage: latest)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 640)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("latest comparison sheet: reference vs current model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text(vm.currentStage)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Text("No 3D preview")
                        .foregroundStyle(.secondary)
                    if let exportError = vm.exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if vm.phase == .done {
                Text(vm.accepted
                     ? "ACCEPTED \(Self.score(vm.finalScore))"
                     : "BEST \(Self.score(vm.finalScore)), below "
                       + Self.score(SculptViewModel.threshold))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(vm.accepted ? .green : .orange)
                if let bestCycle = vm.bestCycle {
                    Text("cycle \(bestCycle) of \(vm.cycles.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let usage = vm.usageSummary {
                    Text(usage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if vm.phase == .running {
                Button("Cancel") { vm.cancel() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("New Photo") { vm.newRun() }
                Button("Quick Look") { vm.quickLook() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(vm.usdzURL == nil)
                Button("Save USDZ...") { vm.saveUSDZ() }
                    .disabled(vm.usdzURL == nil)
                Button("Reveal in Finder") { vm.revealInFinder() }
                    .disabled(vm.outDir == nil)
            }
        }
        .padding(12)
    }

    private static func score(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
