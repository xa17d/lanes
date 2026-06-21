//
//  LanesApp.swift
//  Lanes
//
//  Keyboard-first macOS launcher for switching between parallel work lanes.
//

import SwiftUI

@main
struct LanesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(library: AppCore.shared.library)
        }
    }
}
