//
//  RepositoryProvider.swift
//  lane
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
        let apps = services.apps
        let iterm = services.iterm
        let laneID = lane.id

        // Custom per-repo scripts from <root>/.lanes/config/script-items/repository
        // (read once, reused for every repo).
        let scripts = ScriptItems(shell: services.shell)
        let repoScripts = ScriptItems.executableFiles(
            in: LaneFS.repoScriptItemsDir(in: LaneActions.root(of: lane)))
        let lane = lane

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
                                         apps: apps, iterm: iterm,
                                         scripts: scripts, repoScripts: repoScripts, lane: lane)
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
        apps: AppLauncher, iterm: ITermController,
        scripts: ScriptItems, repoScripts: [URL], lane: Lane
    ) -> [any Item] {
        let path = repoURL.path
        var actions: [any Item] = []

        // PR/CI only when the host is recognized.
        if let remote = git.remote(of: repoURL), let adapter = hosts.adapter(for: remote) {
            let branch = git.branch(of: repoURL) ?? "HEAD"
            let prURL = adapter.prURL(remote, branch: branch)
            let ciURL = adapter.ciURL(remote, branch: branch)
            actions.append(BasicItem(id: "repo:\(path):pr", title: "Open PR", icon: .pullRequest,
                                     keywords: ["pull", "request", "mr"],
                                     run: { try chrome.openInChrome(url: prURL); return .dismiss }))
            actions.append(BasicItem(id: "repo:\(path):ci", title: "Open CI", icon: .ci,
                                     keywords: ["ci", "pipeline", "actions"],
                                     run: { try chrome.openInChrome(url: ciURL); return .dismiss }))
        }

        actions.append(BasicItem(id: "repo:\(path):fork", title: "Open in Fork", icon: .fork,
                                 run: { try apps.open(app: "Fork", path: repoURL); return .dismiss }))
        actions.append(BasicItem(id: "repo:\(path):as", title: "Open in Android Studio", icon: .editor,
                                 run: { try apps.open(app: "Android Studio", path: repoURL); return .dismiss }))
        actions.append(BasicItem(id: "repo:\(path):code", title: "Open in VS Code", icon: .code,
                                 run: { try apps.open(app: "Visual Studio Code", path: repoURL); return .dismiss }))
        actions.append(BasicItem(id: "repo:\(path):term", title: "Open Terminal here", icon: .terminal,
                                 run: {
                                     try iterm.openOrCreate(laneID: laneID, tag: "repo:\(path)", cwd: repoURL, command: nil)
                                     return .dismiss
                                 }))
        actions.append(BasicItem(id: "repo:\(path):finder", title: "Open in Finder", icon: .reveal,
                                 run: { apps.reveal(repoURL); return .dismiss }))

        // Custom per-repo scripts, run with this repo as cwd.
        actions += scripts.repoItems(scripts: repoScripts, repoURL: repoURL, lane: lane)
        return actions
    }
}
