//
//  PanelController.swift
//  lane
//
//  Owns the floating launcher NSPanel: a borderless, non-activating panel with
//  a native material background that sizes itself to the SwiftUI content and
//  hides on Esc or click-away.
//

import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: LanePanel?

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        positionOnActiveScreen(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Construction

    private func makePanel() -> LanePanel {
        let panel = LanePanel(
            contentRect: NSRect(x: 0, y: 0, width: Tokens.Size.panelWidth, height: 320),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.hide() }
        panel.onResignKey = { [weak self] in self?.hide() }

        // contentViewController + NSHostingController makes the window size
        // itself to the SwiftUI content's fitting size.
        let root = RootView(onClose: { [weak self] in self?.hide() })
        panel.contentViewController = NSHostingController(rootView: root)
        return panel
    }

    // MARK: - Placement

    private func positionOnActiveScreen(_ panel: LanePanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        // Sit slightly above center, launcher-style.
        let y = visible.midY - size.height / 2 + visible.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
