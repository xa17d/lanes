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
        // Always open centered on the screen under the mouse. The panel is
        // draggable while visible, but each open re-centers on the active
        // screen (the moved position is not remembered across opens).
        positionOnActiveScreen(panel)
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
            case "r": model.refresh(); return true
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
        case 124:                                        // → drill in
            // Drill when there's no text to move through, or when the caret is
            // already at the end of the query (nothing more to the right).
            if model.query.isEmpty || queryCaretAtEnd { model.drillRight(); return true }
            return false
        case 123:                                        // ← pop (when not editing text)
            if model.query.isEmpty { model.pop(); return true }
            return false
        case 51:                                         // ⌫ backspace
            // With an empty query, backspace steps back instead of doing
            // nothing; with text, it falls through to delete a character.
            if model.query.isEmpty { model.pop(); return true }
            return false
        default:
            return false
        }
    }

    /// Whether the search field's caret sits at (or past) the end of the text,
    /// so a → keypress should drill in rather than move the cursor. Returns
    /// true when no field editor is active (treat as "nothing to the right").
    private var queryCaretAtEnd: Bool {
        guard let editor = (panel?.firstResponder as? NSTextView)
                ?? (panel?.fieldEditor(false, for: nil) as? NSTextView)
        else { return true }
        let selection = editor.selectedRange()
        return selection.location + selection.length >= (editor.string as NSString).length
    }

    // MARK: - Placement

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
