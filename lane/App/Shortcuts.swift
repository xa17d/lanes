//
//  Shortcuts.swift
//  lane
//
//  Global hotkey definition. KeyboardShortcuts uses Carbon hot-key
//  registration, so no Accessibility permission is required.
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggles the launcher panel. Default: ⌥Space.
    static let toggleLane = Self("toggleLane", default: .init(.space, modifiers: [.option]))
}
