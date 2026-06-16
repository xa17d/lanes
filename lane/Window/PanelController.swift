//
//  PanelController.swift
//  lane
//
//  Owns the floating launcher NSPanel. Phase 1: a minimal placeholder panel
//  that the hotkey/status item can toggle. Expanded in Phase 2.
//

import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
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

    private func positionOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        // Sit slightly above center, launcher-style.
        let y = visible.midY - size.height / 2 + visible.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 120),
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
        panel.contentView = NSHostingView(rootView: PlaceholderPanelView())
        return panel
    }
}

private struct PlaceholderPanelView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "road.lanes")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text("Lane")
                .font(.headline)
            Text("Press ⌥Space to toggle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 120)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
