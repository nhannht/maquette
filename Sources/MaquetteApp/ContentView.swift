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
        let images = urls.filter {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true
        }.prefix(1 + ReferenceSet.maxExtras)
        guard !images.isEmpty else { return false }
        start(Array(images))
        return true
    }

    private func openPhotoPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose 1 to \(1 + ReferenceSet.maxExtras) photos of "
            + "a single object (extra photos are further views of it)"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        start(Array(panel.urls.prefix(1 + ReferenceSet.maxExtras)))
    }

    private func start(_ urls: [URL]) {
        guard let coder = coderConfig, let vision = visionConfig else {
            openSettings()
            return
        }
        vm.run(photos: urls, coder: coder, vision: vision,
               coderSeesRenders: settings.coderSeesRenders,
               autoContinue: { [weak settings] in settings?.autoContinue ?? false })
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
                 "until it looks right. Then GLB + USDZ export. Drop up to " +
                 "\(1 + ReferenceSet.maxExtras) photos - extra views of the same " +
                 "object sharpen the result.")
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
                card(title: vm.referenceImages.count > 1 ? "Photos" : "Photo") {
                    let thumbHeight: CGFloat = vm.referenceImages.count > 1 ? 64 : 110
                    HStack(alignment: .top, spacing: 8) {
                        if vm.referenceImages.isEmpty {
                            thumbnail(vm.photoImage, maxHeight: thumbHeight)
                        } else {
                            ForEach(vm.referenceImages.indices, id: \.self) { index in
                                thumbnail(vm.referenceImages[index],
                                          maxHeight: thumbHeight)
                            }
                        }
                        if vm.subjectImage != nil {
                            thumbnail(vm.subjectImage, maxHeight: thumbHeight)
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
            }
            .padding(12)
        }
    }

    /// Tapping a card shows that cycle in the result column (its model when it
    /// exported one, its sheet otherwise). Buttons inside keep priority.
    private func cycleCard(_ cycle: SculptViewModel.CycleRecord) -> some View {
        selectableCard(cycle)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.blue.opacity(0.6), lineWidth: 2)
                .opacity(vm.selectedCycle == cycle.id ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { vm.select(cycle: cycle.id) }
    }

    private func selectableCard(_ cycle: SculptViewModel.CycleRecord) -> some View {
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
                HStack(spacing: 10) {
                    if let usdz = cycle.usdzURL {
                        Button("Quick Look this cycle") { vm.quickLook(usdz) }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                    // Only while the run waits between cycles, and only for
                    // cycles the loop can actually restore: the human eye
                    // outranks the pairwise judge on which model carries on.
                    if let gate = vm.cycleGate,
                       gate.snapshot.availableCycles.contains(cycle.id) {
                        if cycle.id == vm.cycleGate?.selectedBase {
                            Text("base")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.2), in: Capsule())
                        } else {
                            Button("Use as base") { vm.overrideBase(cycle.id) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .help("Carry this cycle's model forward, " +
                                      "overriding the judge's pick.")
                        }
                    }
                }
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
            if case .failed(let message) = vm.phase {
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
                if vm.pendingBrief != nil {
                    briefGate
                } else {
                    // The viewer runs live: sheet or 3D of the viewed cycle
                    // above, the gate controls (or progress) below.
                    VStack(spacing: 12) {
                        viewerArea
                        if vm.cycleGate != nil {
                            cycleGateControls
                        } else {
                            Text("Cycle \(vm.cycles.last?.id ?? 1) of up to \(vm.cycleCap)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if let started = vm.startedAt {
                                TimelineView(.periodic(from: started, by: 1)) { context in
                                    Text(Self.elapsed(from: started, to: context.date))
                                        .font(.title3.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                viewerArea
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Cycle viewer (result column)

    /// The cycle the result column shows: explicit selection first, otherwise
    /// the run's own focus - the best cycle when done, the freshest cycle
    /// with a sheet while running.
    private var viewedCycle: SculptViewModel.CycleRecord? {
        if let id = vm.selectedCycle {
            return vm.cycles.first { $0.id == id }
        }
        if vm.phase == .done, let best = vm.bestCycle {
            return vm.cycles.first { $0.id == best }
        }
        return vm.cycles.last { $0.comparison != nil }
    }

    private var viewerArea: some View {
        let sheet = viewedCycle?.comparison ?? vm.seedComparison
        return VStack(spacing: 8) {
            if vm.scene != nil && sheet != nil {
                Picker("View", selection: $vm.resultTab) {
                    ForEach(SculptViewModel.ResultTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }
            if vm.resultTab == .model, let scene = vm.scene {
                SceneView(scene: scene,
                          options: [.allowsCameraControl, .autoenablesDefaultLighting])
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let sheet {
                Image(nsImage: sheet)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 640)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(sheetCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.phase == .done {
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
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sheetCaption: String {
        guard let cycle = viewedCycle else {
            return "latest result: reference vs current model"
        }
        var caption = "cycle \(cycle.id): reference vs renders"
        if cycle.review != nil && cycle.usdzURL == nil {
            caption += " (no 3D model exported for this cycle)"
        }
        return caption
    }

    // MARK: - Human gates

    /// Gate 1, the input gate: the model's suggested prompt in plain language
    /// plus the reference set - intent beyond the photo AND extra views enter
    /// here, before any coder token is spent.
    private var briefGate: some View {
        VStack(spacing: 12) {
            Text("Here is what I see. Correct or add anything, then start.")
                .font(.callout)
                .foregroundStyle(.secondary)
            referenceEditor
            TextEditor(text: Binding(
                get: { vm.pendingBrief ?? "" },
                set: { vm.pendingBrief = $0 }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: 460, maxHeight: 170)
                .background(.quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 8))
            Button("Start") { vm.approveBrief() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Add, remove, relabel, or re-prime the reference photos while the loop
    /// is parked at the brief gate.
    private var referenceEditor: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(vm.pendingReferences.indices, id: \.self) { index in
                VStack(spacing: 4) {
                    if vm.pendingReferenceThumbs.indices.contains(index) {
                        Image(nsImage: vm.pendingReferenceThumbs[index])
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if index == 0 {
                        Text("primary")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2), in: Capsule())
                    } else {
                        TextField("label (back...)", text: Binding(
                            get: {
                                vm.pendingReferences.indices.contains(index)
                                    ? (vm.pendingReferences[index].label ?? "") : ""
                            },
                            set: { vm.setPendingLabel(index, $0) }))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 84)
                        Button("make primary") { vm.makePendingPrimary(index) }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                    if vm.pendingReferences.count > 1 {
                        Button("remove") { vm.removePendingReference(at: index) }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }
            }
            if vm.pendingReferences.count < 1 + ReferenceSet.maxExtras {
                Button {
                    addReferencesFromPanel()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add view")
                            .font(.caption)
                    }
                    .frame(width: 84, height: 84)
                    .background(.quaternary.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("More photos of the same object: back, open state, detail.")
            }
        }
    }

    private func addReferencesFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Add more views of the same object"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            vm.addPendingReference(url)
        }
    }

    /// Gate 2: the judge's suggested next instruction. Edit it or just go.
    /// Gate 0 (Keep Refining) is the same box before any cycle has run.
    /// Reference edits ride the same pause, collapsed until needed.
    private var cycleGateControls: some View {
        let refining = vm.cycleGate?.snapshot.cycle == 0
        return VStack(spacing: 10) {
            Text(refining
                 ? "What should change? Edit the instruction, then refine."
                 : "Next instruction for the coder - edit or just continue.")
                .font(.callout)
                .foregroundStyle(.secondary)
            DisclosureGroup("Reference photos") {
                referenceEditor
                    .padding(.top, 6)
            }
            .font(.caption)
            .frame(maxWidth: 640)
            TextEditor(text: Binding(
                get: { vm.cycleGate?.critiqueDraft ?? "" },
                set: { vm.cycleGate?.critiqueDraft = $0 }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: 640, maxHeight: 120)
                .background(.quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                if !refining {
                    Button("Use This Model") { vm.resumeCycle(accept: true) }
                }
                Button(refining ? "Refine" : "Next Cycle") {
                    vm.resumeCycle(accept: false)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.bottom, 12)
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
                if vm.phase == .done && vm.resumeSeed != nil {
                    Button("Keep Refining") {
                        guard let coder = coderConfig, let vision = visionConfig else { return }
                        vm.keepRefining(coder: coder, vision: vision,
                                        coderSeesRenders: settings.coderSeesRenders)
                    }
                    .help("Run more cycles: the current best model becomes the " +
                          "incumbent and new attempts must beat it.")
                }
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

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
