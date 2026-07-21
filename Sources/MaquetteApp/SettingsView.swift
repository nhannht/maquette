import SwiftUI
import MaquetteKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Text("Bring your own model. Any OpenAI-compatible endpoint works: " +
                     "hosted (OpenRouter, OpenAI, Anthropic, Moonshot) or local " +
                     "(Ollama, LM Studio - cheaper and fully private, no key needed).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Coder (writes the 3D factory code)") {
                SlotFields(endpoint: $settings.coderEndpoint,
                           model: $settings.coderModel,
                           key: $settings.coderKey,
                           thinkingCap: $settings.coderThinkingCap,
                           requireImage: false,
                           hints: ["coder", "code"])
                Toggle("Show the coder its renders", isOn: $settings.coderSeesRenders)
                Text("Attaches the best cycle's comparison sheet to coding prompts. " +
                     "Needs a multimodal coder (gemini, kimi); turn off for text-only " +
                     "coders like qwen3-coder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SlotTestButton(slot: .coder)
            }
            Section("Loop") {
                Toggle("Auto-continue cycles", isOn: $settings.autoContinue)
                Text("By default the app pauses between cycles with the suggested " +
                     "next instruction so you can edit it or just continue. Turn " +
                     "this on to let the judge drive until it accepts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Judge (scores renders against the photo)") {
                SlotFields(endpoint: $settings.visionEndpoint,
                           model: $settings.visionModel,
                           key: $settings.visionKey,
                           thinkingCap: $settings.visionThinkingCap,
                           requireImage: true,
                           hints: [])
                Text("Must accept images. The judge is only a default: every " +
                     "cycle's model is exported, you pick the winner by eye.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SlotTestButton(slot: .vision)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }
}

/// One slot's fields: provider preset for the simple path, raw endpoint only
/// for Custom, model picker fed by the endpoint's own /models list, optional
/// key, reasoning toggle.
private struct SlotFields: View {
    @Binding var endpoint: String
    @Binding var model: String
    @Binding var key: String
    @Binding var thinkingCap: String
    let requireImage: Bool
    let hints: [String]

    @State private var showPicker = false

    var body: some View {
        let provider = Binding<SettingsStore.Provider>(
            get: { .detect(endpoint) },
            set: { newValue in
                if let preset = newValue.endpoint { endpoint = preset }
            })
        Picker("Provider", selection: provider) {
            ForEach(SettingsStore.Provider.allCases) { candidate in
                Text(candidate.label).tag(candidate)
            }
        }
        if provider.wrappedValue == .custom {
            TextField("Endpoint", text: $endpoint, prompt: Text("https://host/v1"))
        } else {
            LabeledContent("Endpoint", value: endpoint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        HStack {
            TextField("Model ID", text: $model,
                      prompt: Text(SettingsStore.defaultModel))
            Button("Choose...") { showPicker = true }
        }
        SecureField("API key", text: $key,
                    prompt: Text(provider.wrappedValue.isLocal
                                 ? "not needed for local endpoints" : "required"))
        TextField("Thinking cap", text: $thinkingCap, prompt: Text("maximum"))
        Text("Thinking models spend as many tokens as they like by default. " +
             "Enter a token cap to trim cost - enforced on OpenRouter only; " +
             "other endpoints govern their own thinking.")
            .font(.caption)
            .foregroundStyle(.secondary)
        .sheet(isPresented: $showPicker) {
            ModelPickerSheet(endpointString: endpoint, apiKey: key,
                             requireImage: requireImage, hints: hints,
                             selection: $model)
        }
    }
}

/// Lists the endpoint's own /models catalog (OpenRouter serves pricing and
/// image support for free; local endpoints list plain ids). "Cheapest" is the
/// one-click just-works default.
private struct ModelPickerSheet: View {
    let endpointString: String
    let apiKey: String
    let requireImage: Bool
    let hints: [String]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    @State private var models: [ModelInfo] = []
    @State private var search = ""
    @State private var failure: String?

    private var filtered: [ModelInfo] {
        search.isEmpty ? models : models.filter {
            $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search models", text: $search)
                    .textFieldStyle(.roundedBorder)
                Button("Cheapest\(requireImage ? " with vision" : "")") { pickCheapest() }
                    .disabled(models.isEmpty)
                    .help("Picks the lowest-priced model that fits this slot. " +
                          "Free models win by costing zero.")
                Button("Cancel") { dismiss() }
            }
            .padding(12)
            Divider()
            if let failure {
                Text(failure)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if models.isEmpty {
                ProgressView("Fetching model list...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { info in
                    Button {
                        selection = info.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(info.id)
                                Text(info.priceLabel)
                                    .font(.caption)
                                    .foregroundStyle(info.isFree ? .green : .secondary)
                            }
                            Spacer()
                            if info.imageInput {
                                Text("image")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 520, height: 440)
        .task { await fetch() }
    }

    private func fetch() async {
        guard let url = URL(string: endpointString) else {
            failure = "bad endpoint: \(endpointString)"
            return
        }
        do {
            let fetched = try await ModelCatalog.fetch(endpoint: url, apiKey: apiKey)
            models = fetched.sorted {
                ($0.totalPrice ?? .infinity, $0.id) < ($1.totalPrice ?? .infinity, $1.id)
            }
            if models.isEmpty { failure = "endpoint returned an empty model list" }
        } catch {
            failure = "\(error)"
        }
    }

    private func pickCheapest() {
        // Local endpoints do not publish modalities; fall back to the overall
        // cheapest rather than returning nothing for the judge slot.
        let pick = ModelCatalog.cheapest(models, requireImage: requireImage,
                                         preferIDContaining: hints)
            ?? ModelCatalog.cheapest(models, requireImage: false,
                                     preferIDContaining: hints)
        guard let pick else { return }
        selection = pick.id
        dismiss()
    }
}

struct SlotTestButton: View {
    let slot: SettingsStore.Slot
    @Environment(SettingsStore.self) private var settings
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, running
        case ok(String)
        case failed(String)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button("Test connection") { run() }
                .disabled(status == .running || settings.config(for: slot) == nil)
            switch status {
            case .idle:
                if settings.config(for: slot) == nil {
                    Text("fill endpoint and model first")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .running:
                ProgressView().controlSize(.small)
            case .ok(let latency):
                Text("OK, \(latency)").font(.caption).foregroundStyle(.green)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private func run() {
        guard let config = settings.config(for: slot) else { return }
        status = .running
        Task {
            do {
                let latency = try await config.testConnection()
                let s = Double(latency.components.seconds) +
                        Double(latency.components.attoseconds) / 1e18
                status = .ok(String(format: "%.2fs", s))
            } catch {
                status = .failed("\(error)")
            }
        }
    }
}
