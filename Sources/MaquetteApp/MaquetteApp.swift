import SwiftUI
import AppKit

@main
struct MaquetteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup("Maquette") {
            ContentView()
                .environment(settings)
        }
        .defaultSize(width: 900, height: 560)

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}

// A bare SwiftPM executable launches as an accessory process; promote it to a
// regular app so `swift run MaquetteApp` fronts a window with menu bar and Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
