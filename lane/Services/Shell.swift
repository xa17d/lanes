//
//  Shell.swift
//  lane
//
//  Process + AppleScript execution. The app is unsandboxed so it can run git
//  and drive other apps via Apple Events.
//

import Foundation

nonisolated struct Shell: Sendable {
    @discardableResult
    func run(_ launchPath: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let err = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ShellError.nonzeroExit(status: process.terminationStatus,
                                         stderr: err.isEmpty ? out : err)
        }
        return out
    }

    /// Run an AppleScript. Must be called on the main thread (NSAppleScript is
    /// not thread-safe); Lane's launch actions run on the main actor.
    @discardableResult
    func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError(code: 0, message: "Could not compile AppleScript")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            throw AppleScriptError(code: code, message: message)
        }
        return result.stringValue ?? ""
    }
}

nonisolated enum ShellError: LocalizedError {
    case nonzeroExit(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .nonzeroExit(_, let stderr): return stderr
        }
    }
}

nonisolated struct AppleScriptError: LocalizedError {
    let code: Int
    let message: String

    /// errAEEventNotPermitted — automation not authorized.
    var isNotAuthorized: Bool { code == -1743 }
    /// errAETimeout / errOSAStimeout.
    var isTimeout: Bool { code == -1712 || code == -1701 }

    var errorDescription: String? { message }
}
