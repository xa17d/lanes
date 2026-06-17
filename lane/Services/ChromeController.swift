//
//  ChromeController.swift
//  lane
//
//  Focus an existing Chrome tab by URL substring, else open a fallback URL.
//  Chrome is the target browser; if it isn't installed we fall back to the
//  default browser via NSWorkspace and surface a toast.
//

import Foundation
import AppKit

nonisolated struct ChromeController: Sendable {
    let shell: Shell

    private static let appName = "Google Chrome"

    @discardableResult
    func focusOrOpen(urlContaining substring: String, fallback: URL) throws -> String {
        let source = Self.script
            .replacingOccurrences(of: "%SUBSTR%", with: AppleScriptEscaping.quote(substring))
            .replacingOccurrences(of: "%FALLBACK%", with: AppleScriptEscaping.quote(fallback.absoluteString))
        do {
            return try shell.runAppleScript(source)
        } catch let error as AppleScriptError {
            if error.isNotAuthorized {
                throw AutomationError.notAuthorized(app: Self.appName)
            }
            // Most likely Chrome isn't installed: open in the default browser
            // and report it.
            NSWorkspace.shared.open(fallback)
            throw AutomationError.notInstalled(app: Self.appName)
        }
    }

    @discardableResult
    func openInChrome(url: URL) throws -> String {
        try focusOrOpen(urlContaining: url.absoluteString, fallback: url)
    }

    // Verbatim from the spec (§7).
    private static let script = """
    tell application "Google Chrome"
        set wins to windows
        repeat with w in wins
            set idx to 0
            repeat with t in tabs of w
                set idx to idx + 1
                if (URL of t) contains "%SUBSTR%" then
                    set active tab index of w to idx
                    set index of w to 1
                    activate
                    return "focused"
                end if
            end repeat
        end repeat
        if (count of windows) = 0 then make new window
        tell front window to make new tab with properties {URL:"%FALLBACK%"}
        activate
        return "opened"
    end tell
    """
}
