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
        var reasoningKey: String { "reasoning.\(rawValue)" }
    }

    /// Known providers so switching endpoints is one click; Custom exposes the
    /// raw endpoint field.
    enum Provider: String, CaseIterable, Identifiable {
        case openRouter, moonshot, ollama, lmStudio, custom

        var id: String { rawValue }

        var label: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .moonshot: return "Moonshot"
            case .ollama: return "Ollama (local)"
            case .lmStudio: return "LM Studio (local)"
            case .custom: return "Custom..."
            }
        }

        /// nil for custom: the user owns the endpoint field.
        var endpoint: String? {
            switch self {
            case .openRouter: return "https://openrouter.ai/api/v1"
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

    var coderEndpoint: String { didSet { save(.coder) } }
    var coderModel: String { didSet { save(.coder) } }
    var coderKey: String { didSet { saveKey(.coder, coderKey) } }
    var coderReasoning: Bool { didSet { saveBool(coderReasoning, Slot.coder.reasoningKey) } }
    var visionEndpoint: String { didSet { save(.vision) } }
    var visionModel: String { didSet { save(.vision) } }
    var visionKey: String { didSet { saveKey(.vision, visionKey) } }
    var visionReasoning: Bool { didSet { saveBool(visionReasoning, Slot.vision.reasoningKey) } }
    /// Attach the best cycle's renders to codegen prompts. Requires a
    /// multimodal coder; off for text-only coders like qwen3-coder.
    var coderSeesRenders: Bool { didSet { saveBool(coderSeesRenders, Self.coderSeesRendersKey) } }

    init() {
        let defaults = UserDefaults.standard
        coderEndpoint = defaults.string(forKey: Slot.coder.endpointKey) ?? Self.defaultEndpoint
        coderModel = defaults.string(forKey: Slot.coder.modelKey) ?? Self.defaultModel
        coderKey = Keychain.get(account: Slot.coder.keychainAccount) ?? ""
        coderReasoning = Self.bool(defaults, Slot.coder.reasoningKey, default: true)
        visionEndpoint = defaults.string(forKey: Slot.vision.endpointKey) ?? Self.defaultEndpoint
        visionModel = defaults.string(forKey: Slot.vision.modelKey) ?? Self.defaultModel
        visionKey = Keychain.get(account: Slot.vision.keychainAccount) ?? ""
        visionReasoning = Self.bool(defaults, Slot.vision.reasoningKey, default: true)
        coderSeesRenders = Self.bool(defaults, Self.coderSeesRendersKey, default: true)
    }

    func config(for slot: Slot) -> ModelSlotConfig? {
        let endpoint = slot == .coder ? coderEndpoint : visionEndpoint
        let model = slot == .coder ? coderModel : visionModel
        let key = slot == .coder ? coderKey : visionKey
        let reasoning = slot == .coder ? coderReasoning : visionReasoning
        guard let url = URL(string: endpoint), !model.isEmpty else { return nil }
        return ModelSlotConfig(endpoint: url, modelID: model, apiKey: key,
                               reasoning: reasoning)
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

    private static func bool(_ defaults: UserDefaults, _ key: String,
                             default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}
