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

        // Custom per-repo scripts from <root>/.lanes/config/script-items/repository
        // (read once, reused for every repo). The Open PR / Open Terminal here /
        // editor / Finder / CI actions all ship as drop-in examples there — see
        // examples/script-items/repository.
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
                            scripts.repoItems(scripts: repoScripts, repoURL: repoURL,
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
}
