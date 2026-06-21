//
//  AutomationError.swift
//  Lanes
//
//  User-facing errors from driving other apps. Copy is specific and doesn't
//  apologize (§8).
//

import Foundation

nonisolated enum AutomationError: LocalizedError {
    case notAuthorized(app: String)
    case notInstalled(app: String)
    case failed(app: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let app):
            return "Lanes needs permission to control \(app). Grant it in System Settings → Privacy & Security → Automation."
        case .notInstalled(let app):
            return "\(app) isn’t installed."
        case .failed(_, let message):
            return message
        }
    }
}

nonisolated enum AppleScriptEscaping {
    /// Escape a string for interpolation inside an AppleScript double-quoted literal.
    static func quote(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
