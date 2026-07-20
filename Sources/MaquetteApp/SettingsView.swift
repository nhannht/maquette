import SwiftUI
import MaquetteKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Text("Bring your own model. Any OpenAI-compatible endpoint works: " +
                     "hosted (OpenRouter, Moonshot) or local (Ollama, LM Studio - " +
                     "cheaper and fully private, no key needed).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Coder (writes the 3D factory code)") {
                slotFields(endpoint: $settings.coderEndpoint,
                           model: $settings.coderModel,
                           key: $settings.coderKey,
                           reasoning: $settings.coderReasoning)
                Toggle("Show the coder its renders", isOn: $settings.coderSeesRenders)
                Text("Attaches the best cycle's comparison sheet to coding prompts. " +
                     "Needs a multimodal coder (gemini, kimi); turn off for text-only " +
                     "coders like qwen3-coder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SlotTestButton(slot: .coder)
            }
            Section("Judge (scores renders against the photo)") {
                slotFields(endpoint: $settings.visionEndpoint,
                           model: $settings.visionModel,
                           key: $settings.visionKey,
                           reasoning: $settings.visionReasoning)
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

    /// Shared per-slot fields: provider preset up front for the simple path,
    /// raw endpoint only when Custom, key optional, reasoning toggle.
    @ViewBuilder
    private func slotFields(endpoint: Binding<String>, model: Binding<String>,
                            key: Binding<String>,
                            reasoning: Binding<Bool>) -> some View {
        let provider = Binding<SettingsStore.Provider>(
            get: { .detect(endpoint.wrappedValue) },
            set: { newValue in
                if let preset = newValue.endpoint { endpoint.wrappedValue = preset }
            })
        Picker("Provider", selection: provider) {
            ForEach(SettingsStore.Provider.allCases) { candidate in
                Text(candidate.label).tag(candidate)
            }
        }
        if provider.wrappedValue == .custom {
            TextField("Endpoint", text: endpoint,
                      prompt: Text("https://host/v1"))
        } else {
            LabeledContent("Endpoint", value: endpoint.wrappedValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        TextField("Model ID", text: model, prompt: Text(SettingsStore.defaultModel))
        SecureField("API key", text: key,
                    prompt: Text(provider.wrappedValue.isLocal
                                 ? "not needed for local endpoints" : "required"))
        Toggle("Reasoning model", isOn: reasoning)
        Text("Keep ON for models that think before answering (gemini, kimi " +
             "thinking, o-series, qwen -thinking): it caps thinking tokens so the " +
             "answer is not starved. Harmless if the model does not reason.")
            .font(.caption)
            .foregroundStyle(.secondary)
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
