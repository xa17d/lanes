//
//  RepositoryProvider.swift
//  Lanes
//
//  Section 1. One container per discovered repo (subtitle = current branch);
//  its children are the per-repo actions. Branches are read concurrently.
//

import Foundation

nonisolated struct RepositoryProvider: LaneProvider {
    let section = 1
    var displayName: String { "Repositories" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let repos = services.git.discoverRepos(in: lane.url)
        let git = services.git
        let hosts = services.hosts
        let chrome = services.chrome
        let iterm = services.iterm
        let laneID = lane.id

        // Custom per-repo scripts from <root>/.lanes/config/script-items/repository
        // (read once, reused for every repo).
        let scripts = ScriptItems(shell: services.shell)
        let repoScripts = ScriptItems.executableFiles(
            in: LaneFS.repoScriptItemsDir(in: LaneActions.root(of: lane)))
        let lane = lane
        let ticket = TicketProvider.primaryEnv(store: store, baseURL: services.ticketBaseURL)

        // Read branches per-repo concurrently.
        return await withTaskGroup(of: (Int, any Item).self) { group in
            for (index, repoURL) in repos.enumerated() {
                group.addTask {
                    let branch = git.branch(of: repoURL)
                    let item = BasicItem(
                        id: "repo:\(repoURL.path)",
                        title: repoURL.lastPathComponent,
                        subtitle: branch,
                        icon: .repo,
                        keywords: ["repo", "git"],
                        childrenProvider: {
                            Self.actions(repoURL: repoURL, laneID: laneID,
                                         git: git, hosts: hosts, chrome: chrome,
                                         iterm: iterm,
                                         scripts: scripts, repoScripts: repoScripts,
                                         lane: lane, ticket: ticket)
                        }
                    )
                    return (index, item)
                }
            }
            var collected: [(Int, any Item)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func actions(
        repoURL: URL, laneID: UUID,
        git: GitInspector, hosts: HostResolver, chrome: ChromeController,
        iterm: ITermController,
        scripts: ScriptItems, repoScripts: [URL], lane: Lane, ticket: TicketEnv?
    ) -> [any Item] {
        let path = repoURL.path
        var actions: [any Item] = []

        // Open PR only when the host is recognized. (Open PR keeps the built-in
        // Chrome tab-focus behavior; Open CI and the editor/Finder launchers now
        // ship as example script-items — see examples/script-items/repository.)
        if let remote = git.remote(of: repoURL), let adapter = hosts.adapter(for: remote) {
            let branch = git.branch(of: repoURL) ?? "HEAD"
            let prURL = adapter.prURL(remote, branch: branch)
            actions.append(BasicItem(id: "repo:\(path):pr", title: "Open PR", icon: .pullRequest,
                                     keywords: ["pull", "request", "mr"],
                                     run: { try chrome.openInChrome(url: prURL); return .dismiss }))
        }

        // Open Terminal here keeps the built-in tagged iTerm session reuse.
        actions.append(BasicItem(id: "repo:\(path):term", title: "Open Terminal here", icon: .terminal,
                                 run: {
                                     try iterm.openOrCreate(laneID: laneID, tag: "repo:\(path)", cwd: repoURL, command: nil)
                                     return .dismiss
                                 }))

        // Custom per-repo scripts (incl. the editor/Finder launcher examples),
        // run with this repo as cwd.
        actions += scripts.repoItems(scripts: repoScripts, repoURL: repoURL, lane: lane, ticket: ticket)
        return actions
    }
}
