import SwiftUI
import MaquetteKit

struct ContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scale.3d")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Maquette")
                .font(.title2)
            Text("Drop a photo, get a sculpted 3D model. A coder LLM writes procedural " +
                 "geometry, a built-in renderer previews it, a vision model scores it " +
                 "against your photo, and the loop repeats until it looks right.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            slotStatus

            Text("Phase 1 build: model plumbing only. The sculpt loop lands next.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 640, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var slotStatus: some View {
        VStack(spacing: 6) {
            ForEach(SettingsStore.Slot.allCases, id: \.self) { slot in
                HStack(spacing: 8) {
                    Image(systemName: settings.config(for: slot) != nil
                          ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(settings.config(for: slot) != nil ? .green : .secondary)
                    Text("\(slot.label) slot")
                    if let config = settings.config(for: slot) {
                        Text("\(config.modelID) @ \(config.endpoint.host() ?? "?")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Configure...") { openSettings() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }
}
