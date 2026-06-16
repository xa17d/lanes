//
//  LaneApp.swift
//  lane
//
//  Keyboard-first macOS launcher for switching between parallel work tracks.
//

import SwiftUI

@main
struct LaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Placeholder Settings scene; fleshed out in Phase 8. Provides the
        // standard ⌘, hook even though the app is an LSUIElement accessory.
        Settings {
            SettingsPlaceholderView()
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings — coming in a later phase.")
            .padding(40)
            .frame(width: 420)
    }
}
