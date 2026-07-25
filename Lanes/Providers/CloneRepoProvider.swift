//
//  CloneRepoProvider.swift
//  Lanes
//
//  Section 2. A single "Clone repo…" container whose children are the root's
//  known repos (RepoRegistry), so from inside a lane you can search a repo you
//  cloned before and clone it here. Because SubtreeIndex indexes children, the
//  repos are reachable by name straight from the lane's top level.
//
//  Selecting a repo clones it into the lane (hybrid: a `clone-repo` handler if
//  configured, else `git clone`) and re-enters the lane so the new repo shows.
//  A secondary "Add repo to list…" action seeds a URL you have not cloned yet.
//

import Foundation

nonisolated struct CloneRepoProvider: LaneProvider {
    let section = 2
    var displayName: String { "Clone repo" }

    func items(for lane: Lane, store: LaneStore, services: Services) async -> [any Item] {
        let root = LaneActions.root(of: lane)
        let registry = RepoRegistry(root: root)
        let cloner = RepoCloner(shell: services.shell)

        let container = BasicItem(
            id: "clone:container",
            title: "Clone repo…",
            icon: .repo,
            keywords: ["clone", "repo", "git", "checkout"],
            childrenProvider: {
                // Read the registry live so an "Add repo…" (or a fresh clone)
                // shows up when this level is reloaded.
                var kids: [any Item] = registry.known().map { repo in
                    Self.repoItem(repo, lane: lane, root: root, cloner: cloner, registry: registry)
                }
                kids.append(Self.addItem(lane: lane, root: root, registry: registry))
                return kids
            }
        )
        return [container]
    }

    // MARK: - Items

    private static func repoItem(_ repo: KnownRepo, lane: Lane, root: URL,
                                 cloner: RepoCloner, registry: RepoRegistry) -> any Item {
        // A single stat (the exact clone-collision predicate) — no repo scan.
        let alreadyHere = FileManager.default.fileExists(
            atPath: lane.url.appendingPathComponent(repo.name).path)
        let identity = [repo.owner, repo.host].compactMap { $0 }.joined(separator: " · ")
        let subtitle: String = {
            let base = identity.isEmpty ? repo.url : identity
            return alreadyHere ? "\(base)  ·  already in this lane" : base
        }()
        return BasicItem(
            id: "clone:\(RepoRegistry.canonicalKey(for: repo))",
            title: repo.name,
            subtitle: subtitle,
            icon: .repo,
            keywords: ["clone", "repo", "git", repo.owner, repo.host].compactMap { $0 },
            run: {
                let outcome = try cloner.clone(repo, into: lane, root: root)
                registry.remember(url: repo.url)   // bump recency
                // Re-enter the lane either way so the new repo lists; a non-fatal
                // warning is surfaced but never blocks the refresh.
                switch outcome {
                case .cloned:
                    return .enter(lane)
                case .clonedWithWarnings(let stderr):
                    let detail = stderr.isEmpty ? "" : "\n\(stderr)"
                    return .enterWithNotice(lane, notice: "Cloned “\(repo.name)” with warnings.\(detail)")
                }
            }
        )
    }

    private static func addItem(lane: Lane, root: URL, registry: RepoRegistry) -> any Item {
        BasicItem(
            id: "clone:add",
            title: "Add repo to list…",
            icon: .add,
            keywords: ["add", "clone", "repo", "url"],
            isSecondary: true,
            run: {
                .pushInput(InputRequest(title: "Add repo",
                                        placeholder: "Clone URL (git@… or https://…)") { input in
                    let url = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { throw InputError(message: "Enter a clone URL.") }
                    guard RepoRegistry.makeRepo(url: url, now: Date()) != nil else {
                        throw InputError(message: "Not a recognizable clone URL.")
                    }
                    registry.remember(url: url)
                    return .pop   // back to the "Clone repo…" list, now including it
                })
            }
        )
    }
}
