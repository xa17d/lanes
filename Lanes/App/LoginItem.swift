//
//  LoginItem.swift
//  Lanes
//
//  "Launch at login" via the modern ServiceManagement API (macOS 13+). Registers
//  the main app itself as a login item — no helper tool or login-items list
//  surgery needed. Only meaningful for the installed app (e.g. in /Applications);
//  registering a copy run from DerivedData during development is a no-op-ish.
//

import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else {
            if service.status == .enabled { try service.unregister() }
        }
    }
}
