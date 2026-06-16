//
//  ITermController.swift
//  lane
//
//  Find-or-create a tagged iTerm2 session. Sessions are tagged by name with a
//  stable sentinel «lane:<trackID>:<tag>» so they can be re-focused later.
//

import Foundation

nonisolated struct ITermController: Sendable {
    let shell: Shell

    private static let appName = "iTerm"

    /// Find a session whose name contains the sentinel and select it; else
    /// create a window, name it, cd, and run `command` (if any).
    @discardableResult
    func openOrCreate(trackID: UUID, tag: String, cwd: URL, command: String?) throws -> String {
        let sentinel = "«lane:\(trackID.uuidString):\(tag)»"
        let source = Self.script
            .replacingOccurrences(of: "%SENTINEL%", with: AppleScriptEscaping.quote(sentinel))
            .replacingOccurrences(of: "%CWD%", with: AppleScriptEscaping.quote(cwd.path))
            .replacingOccurrences(of: "%COMMAND%", with: AppleScriptEscaping.quote(command ?? ""))
        do {
            return try shell.runAppleScript(source)
        } catch let error as AppleScriptError {
            if error.isNotAuthorized {
                throw AutomationError.notAuthorized(app: Self.appName)
            }
            throw AutomationError.notInstalled(app: Self.appName)
        }
    }

    // Verbatim from the spec (§7), with named placeholders.
    private static let script = """
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if name of s contains "%SENTINEL%" then
                        select w
                        tell t to select
                        tell s to select
                        activate
                        return "focused"
                    end if
                end repeat
            end repeat
        end repeat
        set newWindow to (create window with default profile)
        tell current session of newWindow
            set name to "%SENTINEL%"
            write text "cd " & quoted form of "%CWD%"
            if "%COMMAND%" is not "" then write text "%COMMAND%"
        end tell
        activate
        return "created"
    end tell
    """
}
