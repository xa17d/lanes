//
//  Permissions.swift
//  lane
//
//  Automation (TCC) helpers. The first Apple Event to Chrome/iTerm triggers
//  the macOS Automation prompt; denial surfaces AppleScript error -1743, which
//  the controllers map to AutomationError.notAuthorized. No Accessibility
//  permission is needed anywhere.
//

import Foundation
import AppKit

@MainActor
enum Permissions {
    static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    static func openAutomationSettings() {
        NSWorkspace.shared.open(automationSettingsURL)
    }
}
