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
    private let panel = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        statusItem = StatusItemController(
            onToggle: { [weak self] in self?.panel.toggle() },
            onSettings: { AppDelegate.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        KeyboardShortcuts.onKeyUp(for: .toggleLane) { [weak self] in
            self?.panel.toggle()
        }

        // Debug aid: LANE_AUTOSHOW=1 shows the panel on launch (used for
        // headless smoke tests). Inert without the env var.
        if ProcessInfo.processInfo.environment["LANE_AUTOSHOW"] == "1" {
            panel.show()
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
