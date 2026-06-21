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
    var hosts: HostResolver
    var chrome: ChromeController
    var iterm: ITermController
    var apps: AppLauncher
    var jiraBaseURL: @Sendable () -> URL?

    init(
        shell: Shell = Shell(),
        hosts: HostResolver = HostResolver(),
        jiraBaseURL: @escaping @Sendable () -> URL? = { nil }
    ) {
        self.shell = shell
        self.git = GitInspector(shell: shell)
        self.hosts = hosts
        self.chrome = ChromeController(shell: shell)
        self.iterm = ITermController(shell: shell)
        self.apps = AppLauncher(shell: shell)
        self.jiraBaseURL = jiraBaseURL
    }
}
