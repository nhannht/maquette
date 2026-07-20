import SwiftUI
import MaquetteKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Text("Bring your own key. Any OpenAI-compatible endpoint works " +
                     "(Moonshot, OpenRouter, ...). Kimi K2.5 is multimodal, so both " +
                     "slots can use the same model and key.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Coder model (writes the 3D factory code)") {
                TextField("Endpoint", text: $settings.coderEndpoint,
                          prompt: Text(SettingsStore.defaultEndpoint))
                TextField("Model ID", text: $settings.coderModel,
                          prompt: Text(SettingsStore.defaultModel))
                SecureField("API key", text: $settings.coderKey)
                SlotTestButton(slot: .coder)
            }
            Section("Vision model (scores renders against the photo)") {
                TextField("Endpoint", text: $settings.visionEndpoint,
                          prompt: Text(SettingsStore.defaultEndpoint))
                TextField("Model ID", text: $settings.visionModel,
                          prompt: Text(SettingsStore.defaultModel))
                SecureField("API key", text: $settings.visionKey)
                SlotTestButton(slot: .vision)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
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
                    Text("fill endpoint, model, and key first")
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
