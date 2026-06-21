//
//  ITermController.swift
//  lane
//
//  Find-or-create a tagged iTerm2 session. Sessions are tagged with a stable
//  sentinel «lane:<laneID>:<tag>» stored in an iTerm2 user-defined variable
//  (`user.lane`) so they can be re-focused later.
//
//  NB: the tag is deliberately NOT stored in the session `name`. iTerm2 lets
//  the running shell/program rewrite the session name (via the prompt or OSC
//  title escapes) within moments of launch, which wiped out a name-based
//  sentinel and made every reopen spawn a new window. User-defined variables
//  are not touched by title updates, so they survive for the session's life.
//

import Foundation

nonisolated struct ITermController: Sendable {
    let shell: Shell

    private static let appName = "iTerm"

    /// Find the session tagged with the sentinel and focus it; else create a
    /// window, tag it, cd, and run `command` (if any).
    @discardableResult
    func openOrCreate(laneID: UUID, tag: String, cwd: URL, command: String?) throws -> String {
        let sentinel = "«lane:\(laneID.uuidString):\(tag)»"
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

    // Tag/lookup uses the `user.lane` session variable (not the volatile
    // session name). Reading an unset variable can error, so guard it.
    //
    // Focus ordering matters: `select w` followed by app-level `activate` does
    // NOT reliably foreground the chosen window when another iTerm window is
    // already key — `activate` re-asserts the previously-frontmost window and
    // the wrong one stays on top. To land on the right window without flashing
    // the wrong one:
    //   1. Pre-select the matched window/tab/session BEFORE foregrounding, so the
    //      target is already iTerm's current window when it comes forward.
    //   2. `activate` to foreground iTerm.
    //   3. Short delay to let the window-server foreground race settle.
    //   4. Re-select the same window LAST (re-matched by sentinel, since iTerm
    //      window references don't survive being held across the activate) so the
    //      window selection is the final, authoritative action.
    private static let script = """
    tell application "iTerm2"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    set theTag to ""
                    try
                        tell s to set theTag to (variable named "user.lane")
                    end try
                    if theTag is "%SENTINEL%" then
                        tell t to select
                        tell s to select
                        select w
                        activate
                        delay 0.15
                        repeat with w2 in windows
                            repeat with t2 in tabs of w2
                                repeat with s2 in sessions of t2
                                    set tg2 to ""
                                    try
                                        tell s2 to set tg2 to (variable named "user.lane")
                                    end try
                                    if tg2 is "%SENTINEL%" then
                                        tell t2 to select
                                        tell s2 to select
                                        select w2
                                    end if
                                end repeat
                            end repeat
                        end repeat
                        return "focused"
                    end if
                end repeat
            end repeat
        end repeat
        set newWindow to (create window with default profile)
        tell current session of newWindow
            set variable named "user.lane" to "%SENTINEL%"
            write text "cd " & quoted form of "%CWD%"
            if "%COMMAND%" is not "" then write text "%COMMAND%"
        end tell
        activate
        return "created"
    end tell
    """
}
