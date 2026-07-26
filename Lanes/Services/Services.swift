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
}
