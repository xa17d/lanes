//
//  LanePanel.swift
//  lane
//
//  Borderless NSPanel that can still become key so the search field accepts
//  typing. Routes Esc (cancelOperation) and click-away (resignKey) to the
//  controller.
//

import AppKit

@MainActor
final class LanePanel: NSPanel {
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Keep the top edge fixed as the content height changes (the list grows
    /// downward instead of the whole panel jumping upward).
    override func setContentSize(_ size: NSSize) {
        let oldTop = frame.maxY
        super.setContentSize(size)
        if isVisible {
            var origin = frame.origin
            origin.y = oldTop - frame.height
            setFrameOrigin(origin)
        }
    }
}
