//
//  SettingsWindowController.swift
//  Lanes
//
//  Hosts SettingsView in a plain NSWindow. For an LSUIElement accessory app
//  the SwiftUI Settings scene + showSettingsWindow: selector is unreliable
//  (often opens nothing), so we drive the window directly.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let library: LaneLibrary
    private let nav = SettingsNavigation()
    private var window: NSWindow?

    init(library: LaneLibrary) {
        self.library = library
    }

    /// Show the Settings window, optionally jumping to `pane`.
    func show(pane: SettingsPane? = nil) {
        if let pane { nav.pane = pane }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(library: library, nav: nav))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Lanes Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.contentMinSize = NSSize(width: 720, height: 480)
            // Set the initial size explicitly: NavigationSplitView reports a
            // flexible fitting size, so the SwiftUI idealHeight alone doesn't
            // determine the opening height.
            window.setContentSize(NSSize(width: 760, height: 710))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
