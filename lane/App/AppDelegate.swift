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
        if rootOverride == nil && core.library.root == nil {
            AppDelegate.openSettings()
        }

        // Debug aid: LANE_AUTOSHOW=1 shows the panel on launch (used for
        // headless smoke tests). Inert without the env var.
        if ProcessInfo.processInfo.environment["LANE_AUTOSHOW"] == "1" {
            core.panel.show()
        }
    }

    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 14+ renamed the selector from Preferences to Settings.
        if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
