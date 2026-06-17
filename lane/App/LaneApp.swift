//
//  LaneApp.swift
//  lane
//
//  Keyboard-first macOS launcher for switching between parallel work lanes.
//

import SwiftUI

@main
struct LaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(library: AppCore.shared.library)
        }
    }
}
