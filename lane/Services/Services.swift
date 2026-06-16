//
//  Services.swift
//  lane
//
//  Dependency bundle injected into providers. Phase 4 establishes the type;
//  the concrete OS-integration services (shell, git, hosts, chrome, iterm,
//  apps) are added in Phase 6.
//

import Foundation

nonisolated struct Services: Sendable {
    var jiraBaseURL: @Sendable () -> URL?

    init(jiraBaseURL: @escaping @Sendable () -> URL? = { nil }) {
        self.jiraBaseURL = jiraBaseURL
    }
}
