import Foundation
import SwiftUI
import MaquetteKit

/// Endpoint + model IDs + toggles persist in UserDefaults; API keys go to the
/// Keychain. An empty key is valid: local endpoints (Ollama, LM Studio) are
/// keyless.
@MainActor
@Observable
final class SettingsStore {
    /// One instance per process: SwiftUI constructs the App struct more than
    /// once, and each SettingsStore() init reads both Keychain items - with a
    /// fresh instance per construction that meant 2 items x N constructions
    /// permission prompts at launch.
    static let shared = SettingsStore()
    enum Slot: String, CaseIterable {
        case coder, vision

        var label: String { self == .coder ? "Coder" : "Judge" }
        var keychainAccount: String { "apikey.\(rawValue)" }
        var endpointKey: String { "endpoint.\(rawValue)" }
        var modelKey: String { "model.\(rawValue)" }
        var thinkingCapKey: String { "thinkingCap.\(rawValue)" }
    }

    /// Known providers so switching endpoints is one click; Custom exposes the
    /// raw endpoint field.
    enum Provider: String, CaseIterable, Identifiable {
        case openRouter, openAI, anthropic, moonshot, ollama, lmStudio, custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openAI: return "OpenAI"
            case .anthropic: return "Anthropic (Claude)"
            case .moonshot: return "Moonshot (Kimi)"
            case .ollama: return "Ollama (local)"
            case .lmStudio: return "LM Studio (local)"
            case .custom: return "Custom..."
            }
        }

        /// nil for custom: the user owns the endpoint field. Anthropic serves
        /// the OpenAI-compatible chat surface on its regular /v1 base (the
        /// "OpenAI SDK compatibility" layer); a plain Claude API key works.
        var endpoint: String? {
            switch self {
            case .openRouter: return "https://openrouter.ai/api/v1"
            case .openAI: return "https://api.openai.com/v1"
            case .anthropic: return "https://api.anthropic.com/v1"
            case .moonshot: return "https://api.moonshot.ai/v1"
            case .ollama: return "http://127.0.0.1:11434/v1"
            case .lmStudio: return "http://127.0.0.1:1234/v1"
            case .custom: return nil
            }
        }

        var isLocal: Bool { self == .ollama || self == .lmStudio }

        static func detect(_ endpoint: String) -> Provider {
            allCases.first { $0.endpoint == endpoint } ?? .custom
        }
    }

    static let defaultEndpoint = "https://api.moonshot.ai/v1"
    static let defaultModel = "kimi-k2.5"
    static let coderSeesRendersKey = "coderSeesRenders"
    static let autoContinueKey = "autoContinueCycles"

    var coderEndpoint: String { didSet { save(.coder) } }
    var coderModel: String { didSet { save(.coder) } }
    var coderKey: String { didSet { saveKey(.coder, coderKey) } }
    /// Thinking cap as typed; empty means maximum (no cap sent).
    var coderThinkingCap: String { didSet { saveString(coderThinkingCap, Slot.coder.thinkingCapKey) } }
    var visionEndpoint: String { didSet { save(.vision) } }
    var visionModel: String { didSet { save(.vision) } }
    var visionKey: String { didSet { saveKey(.vision, visionKey) } }
    var visionThinkingCap: String { didSet { saveString(visionThinkingCap, Slot.vision.thinkingCapKey) } }
    /// Attach the best cycle's renders to codegen prompts. Requires a
    /// multimodal coder; off for text-only coders like qwen3-coder.
    var coderSeesRenders: Bool { didSet { saveBool(coderSeesRenders, Self.coderSeesRendersKey) } }
    /// Skip the between-cycle confirmation and let the judge drive until it
    /// accepts. Default off: the app pauses each cycle with the suggested
    /// next instruction. Read live at each cycle boundary.
    var autoContinue: Bool { didSet { saveBool(autoContinue, Self.autoContinueKey) } }

    init() {
        let defaults = UserDefaults.standard
        coderEndpoint = defaults.string(forKey: Slot.coder.endpointKey) ?? Self.defaultEndpoint
        coderModel = defaults.string(forKey: Slot.coder.modelKey) ?? Self.defaultModel
        coderKey = Keychain.get(account: Slot.coder.keychainAccount) ?? ""
        coderThinkingCap = defaults.string(forKey: Slot.coder.thinkingCapKey) ?? ""
        visionEndpoint = defaults.string(forKey: Slot.vision.endpointKey) ?? Self.defaultEndpoint
        visionModel = defaults.string(forKey: Slot.vision.modelKey) ?? Self.defaultModel
        visionKey = Keychain.get(account: Slot.vision.keychainAccount) ?? ""
        visionThinkingCap = defaults.string(forKey: Slot.vision.thinkingCapKey) ?? ""
        coderSeesRenders = Self.bool(defaults, Self.coderSeesRendersKey, default: true)
        autoContinue = Self.bool(defaults, Self.autoContinueKey, default: false)
    }

    func config(for slot: Slot) -> ModelSlotConfig? {
        let endpoint = slot == .coder ? coderEndpoint : visionEndpoint
        let model = slot == .coder ? coderModel : visionModel
        let key = slot == .coder ? coderKey : visionKey
        let cap = Int((slot == .coder ? coderThinkingCap : visionThinkingCap)
            .trimmingCharacters(in: .whitespaces))
        guard let url = URL(string: endpoint), !model.isEmpty else { return nil }
        return ModelSlotConfig(endpoint: url, modelID: model, apiKey: key,
                               thinkingCap: (cap ?? 0) > 0 ? cap : nil)
    }

    private func save(_ slot: Slot) {
        let defaults = UserDefaults.standard
        defaults.set(slot == .coder ? coderEndpoint : visionEndpoint, forKey: slot.endpointKey)
        defaults.set(slot == .coder ? coderModel : visionModel, forKey: slot.modelKey)
    }

    private func saveKey(_ slot: Slot, _ value: String) {
        if value.isEmpty {
            Keychain.delete(account: slot.keychainAccount)
        } else {
            try? Keychain.set(value, account: slot.keychainAccount)
        }
    }

    private func saveBool(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveString(_ value: String, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String,
                             default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}
