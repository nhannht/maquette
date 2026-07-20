import Foundation
import SwiftUI
import MaquetteKit

/// Endpoint + model IDs persist in UserDefaults; API keys go to the Keychain.
@MainActor
@Observable
final class SettingsStore {
    enum Slot: String, CaseIterable {
        case coder, vision

        var label: String { self == .coder ? "Coder" : "Vision" }
        var keychainAccount: String { "apikey.\(rawValue)" }
        var endpointKey: String { "endpoint.\(rawValue)" }
        var modelKey: String { "model.\(rawValue)" }
    }

    static let defaultEndpoint = "https://api.moonshot.ai/v1"
    static let defaultModel = "kimi-k2.5"

    var coderEndpoint: String { didSet { save(.coder) } }
    var coderModel: String { didSet { save(.coder) } }
    var coderKey: String { didSet { saveKey(.coder, coderKey) } }
    var visionEndpoint: String { didSet { save(.vision) } }
    var visionModel: String { didSet { save(.vision) } }
    var visionKey: String { didSet { saveKey(.vision, visionKey) } }

    init() {
        let defaults = UserDefaults.standard
        coderEndpoint = defaults.string(forKey: Slot.coder.endpointKey) ?? Self.defaultEndpoint
        coderModel = defaults.string(forKey: Slot.coder.modelKey) ?? Self.defaultModel
        coderKey = Keychain.get(account: Slot.coder.keychainAccount) ?? ""
        visionEndpoint = defaults.string(forKey: Slot.vision.endpointKey) ?? Self.defaultEndpoint
        visionModel = defaults.string(forKey: Slot.vision.modelKey) ?? Self.defaultModel
        visionKey = Keychain.get(account: Slot.vision.keychainAccount) ?? ""
    }

    func config(for slot: Slot) -> ModelSlotConfig? {
        let endpoint = slot == .coder ? coderEndpoint : visionEndpoint
        let model = slot == .coder ? coderModel : visionModel
        let key = slot == .coder ? coderKey : visionKey
        guard let url = URL(string: endpoint), !model.isEmpty, !key.isEmpty else { return nil }
        return ModelSlotConfig(endpoint: url, modelID: model, apiKey: key)
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
}
