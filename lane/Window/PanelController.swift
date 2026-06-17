//
//  PanelController.swift
//  lane
//
//  Owns the floating launcher NSPanel and the keyboard handling. Keys are
//  intercepted with a local NSEvent monitor (so the search field keeps text
//  input while ↑↓↵→←/esc drive navigation) and routed into LaneModel.
//

import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private let model: LaneModel
    private var panel: LanePanel?
    private var keyMonitor: Any?

    /// Where the user last dragged the panel, stored as the top-left anchor
    /// (the panel grows downward, keeping its top fixed). In-memory for the
    /// session, like the navigation state — a fresh launch re-centers. `nil`
    /// until moved.
    private var userTopLeft: NSPoint?
    /// True while *we* are positioning the panel, so our own moves aren't
    /// mistaken for a user drag.
    private var repositioning = false
    private var moveObserver: Any?

    init(model: LaneModel) {
        self.model = model
        model.onClose = { [weak self] in self?.hide() }
    }

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
        model.reopen()
        model.panelAppeared = false
        installKeyMonitor()
        restorePosition(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Drive the fade/scale-in (RootView animates on panelAppeared).
        DispatchQueue.main.async { [weak self] in self?.model.panelAppeared = true }
    }

    func hide() {
        model.panelAppeared = false
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
        panel.isMovableByWindowBackground = true   // drag from any empty area
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.model.escape() }
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.contentViewController = NSHostingController(rootView: RootView(model: model))

        // Remember a user drag so the panel reopens where they left it.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, !self.repositioning else { return }
                self.userTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            }
        }
        return panel
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard panel?.isKeyWindow == true else { return false }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "w": model.onClose(); return true   // close from any depth (Esc only steps back)
            case "r": model.reloadCurrent(); return true
            case ",": model.onOpenSettings(); return true
            case "n" where model.stack.isEmpty: model.newLane(); return true
            case "A" where model.stack.isEmpty: model.toggleArchived(); return true
            default: return false
            }
        }

        // In input mode only confirm/cancel are intercepted; everything else
        // (incl. arrows for cursor movement) edits the text field.
        if model.isInputMode {
            switch event.keyCode {
            case 36, 76: model.confirm(); return true
            case 53: model.escape(); return true
            default: return false
            }
        }

        switch event.keyCode {
        case 125: model.moveSelection(1);  return true   // ↓
        case 126: model.moveSelection(-1); return true   // ↑
        case 36, 76: model.confirm(); return true        // return / enter
        case 53: model.escape(); return true             // esc
        case 124:                                        // → drill in (when not editing text)
            if model.query.isEmpty { model.drillRight(); return true }
            return false
        case 123:                                        // ← pop (when not editing text)
            if model.query.isEmpty { model.pop(); return true }
            return false
        default:
            return false
        }
    }

    // MARK: - Placement

    /// Reuse the user's dragged position if it's still on a visible screen;
    /// otherwise center on the screen under the mouse.
    private func restorePosition(_ panel: LanePanel) {
        repositioning = true
        defer { repositioning = false }
        if let topLeft = userTopLeft {
            let origin = NSPoint(x: topLeft.x, y: topLeft.y - panel.frame.height)
            let frame = NSRect(origin: origin, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                panel.setFrameOrigin(origin)
                return
            }
        }
        positionOnActiveScreen(panel)
    }

    private func positionOnActiveScreen(_ panel: LanePanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2 + visible.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
