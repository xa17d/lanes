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

        // Custom per-repo scripts from <root>/.lanes/config/script/repository
        // (read once, reused for every repo). The Open PR / Open Terminal here /
        // editor / Finder / CI actions all ship as drop-in examples there — see
        // examples/script/repository.
        let scripts = ScriptItems(shell: services.shell)
        let root = LaneActions.root(of: lane)
        let repoScripts = ScriptItems.effectiveScripts(
            in: LaneFS.repoScriptDir(in: root), root: root)
        let lane = lane
        let ticket = TicketProvider.primaryEnv(store: store, baseURL: services.ticketBaseURL)

        // Read branch + origin URL per-repo concurrently.
        let collected = await withTaskGroup(of: (Int, any Item, String?).self) { group in
            for (index, repoURL) in repos.enumerated() {
                group.addTask {
                    let branch = git.branch(of: repoURL)
                    let remote = git.remoteURL(of: repoURL)
                    let item = BasicItem(
                        id: "repo:\(repoURL.path)",
                        title: repoURL.lastPathComponent,
                        subtitle: branch,
                        icon: .repo,
                        keywords: ["repo", "git"],
                        childrenProvider: {
                            scripts.repoItems(scripts: repoScripts, repoURL: repoURL,
                                              lane: lane, ticket: ticket)
                        }
                    )
                    return (index, item, remote)
                }
            }
            var out: [(Int, any Item, String?)] = []
            for await triple in group { out.append(triple) }
            return out.sorted { $0.0 < $1.0 }
        }

        // Record the origins we found so a future lane can clone them again
        // (best-effort; writes only when the known-repos list actually changes).
        RepoRegistry(root: root).harvest(collected.compactMap { $0.2 })
        return collected.map { $0.1 }
    }
}
