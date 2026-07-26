//
//  Services.swift
//  Lanes
//
//  Dependency bundle injected into providers. Every side effect (shell, git,
//  browser, terminal, launchers) lives here.
//

import Foundation

nonisolated struct Services: Sendable {
    var shell: Shell
    var git: GitInspector
    var chrome: ChromeController
    var apps: AppLauncher
    var ticketBaseURL: @Sendable () -> URL?

    init(
        shell: Shell = Shell(),
        ticketBaseURL: @escaping @Sendable () -> URL? = { nil }
    ) {
        self.shell = shell
        self.git = GitInspector(shell: shell)
        self.chrome = ChromeController(shell: shell)
        self.apps = AppLauncher(shell: shell)
        self.ticketBaseURL = ticketBaseURL
    }

    /// The lifecycle-hook runner, wired to this bundle's shell + ticket base URL
    /// (so callers don't rebuild it — or re-thread `baseURL` — at every site).
    var hooks: LaneHooks { LaneHooks(shell: shell, baseURL: ticketBaseURL) }

    /// The custom-script runner, wired to this bundle's shell.
    var scripts: ScriptItems { ScriptItems(shell: shell) }
}
