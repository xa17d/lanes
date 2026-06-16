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
}
