//
//  AppDelegate.swift
//  lane
//
//  Owns the status item, global hotkey wiring, and the launcher panel.
//

import AppKit
import KeyboardShortcuts

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private let core = AppCore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        // Dev/test override: LANE_ROOT points the library at a folder without
        // having to configure it in Settings.
        let rootOverride = ProcessInfo.processInfo.environment["LANE_ROOT"]
        if let rootOverride {
            core.library.setRoot(URL(fileURLWithPath: rootOverride, isDirectory: true))
        }
        core.model.onOpenSettings = { AppDelegate.openSettings() }

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.core.panel.toggle() },
            onSettings: { AppDelegate.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        KeyboardShortcuts.onKeyUp(for: .toggleLane) { [weak self] in
            self?.core.panel.toggle()
        }

        // First launch with no root → prompt for it before showing the list.
        // Deferred so the SwiftUI Settings scene is fully wired before we ask
        // it to open (otherwise the action is a no-op).
        if rootOverride == nil && core.library.root == nil {
            DispatchQueue.main.async { AppDelegate.openSettings() }
        }

        // Debug aid: LANE_AUTOSHOW=1 shows the panel on launch (used for
        // headless smoke tests). Inert without the env var.
        if ProcessInfo.processInfo.environment["LANE_AUTOSHOW"] == "1" {
            core.panel.show()
        }
    }

    static func openSettings() {
        AppCore.shared.settings.show()
    }
}
