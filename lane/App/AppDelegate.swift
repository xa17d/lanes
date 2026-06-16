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
    private let library = TrackLibrary()
    private lazy var model = LaneModel(
        library: library,
        services: Services(jiraBaseURL: {
            UserDefaults.standard.string(forKey: "jiraBaseURL").flatMap { URL(string: $0) }
        }),
        registry: .default
    )
    private lazy var panel = PanelController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory app: no Dock icon, lives in the menu bar.
        NSApp.setActivationPolicy(.accessory)

        // Dev/test override: LANE_ROOT points the library at a folder without
        // having to configure it in Settings.
        if let rootPath = ProcessInfo.processInfo.environment["LANE_ROOT"] {
            library.setRoot(URL(fileURLWithPath: rootPath, isDirectory: true))
        }
        model.onOpenSettings = { AppDelegate.openSettings() }

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
