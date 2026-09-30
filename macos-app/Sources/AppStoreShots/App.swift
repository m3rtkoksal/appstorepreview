import AppKit
import SwiftUI

@main
struct AppStoreShotsApp: App {
    @StateObject private var document = Document()

    init() {
        // Needed when launched via `swift run` (no .app bundle) so the window and Dock icon appear.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("App Store Görselleri") {
            ContentView()
                .environmentObject(document)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
