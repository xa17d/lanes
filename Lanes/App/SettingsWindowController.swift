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
    private var window: NSWindow?

    init(library: LaneLibrary) {
        self.library = library
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(library: library))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Lanes Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.contentMinSize = NSSize(width: 720, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
