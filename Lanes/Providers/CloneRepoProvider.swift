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
//  A "Clone from URL…" action pastes a URL and clones it right away; the list
//  fills itself from what you actually clone (no separate "add to list" step).
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
                // Read the registry live so a freshly cloned repo shows up when
                // this level is reloaded.
                var kids: [any Item] = registry.known().map { repo in
                    Self.repoItem(repo, lane: lane, root: root, cloner: cloner, registry: registry)
                }
                kids.append(Self.cloneFromURLItem(lane: lane, root: root, cloner: cloner, registry: registry))
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
            run: { try performClone(repo, lane: lane, root: root, cloner: cloner, registry: registry) }
        )
    }

    private static func cloneFromURLItem(lane: Lane, root: URL,
                                         cloner: RepoCloner, registry: RepoRegistry) -> any Item {
        BasicItem(
            id: "clone:from-url",
            title: "Clone from URL…",
            icon: .add,
            keywords: ["clone", "url", "ssh", "https", "git", "new", "paste"],
            isSecondary: true,
            run: {
                .pushInput(InputRequest(title: "Clone repo",
                                        placeholder: "Clone URL (git@… or https://…)") { input in
                    let url = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { throw InputError(message: "Enter a clone URL.") }
                    guard let repo = RepoRegistry.makeRepo(url: url, now: Date()) else {
                        throw InputError(message: "Not a recognizable clone URL.")
                    }
                    // Clone right away; `remember` (inside performClone) adds it to
                    // the list, so next time it's a one-tap entry.
                    return try performClone(repo, lane: lane, root: root, cloner: cloner, registry: registry)
                })
            }
        )
    }

    /// Clone `repo` into `lane`, record it in the known-repos list, and re-enter
    /// the lane so the new repo shows. A non-fatal warning (a non-zero exit that
    /// still produced the repo) is surfaced but never blocks the refresh.
    private static func performClone(_ repo: KnownRepo, lane: Lane, root: URL,
                                     cloner: RepoCloner, registry: RepoRegistry) throws -> RunOutcome {
        let outcome = try cloner.clone(repo, into: lane, root: root)
        registry.remember(url: repo.url)
        switch outcome {
        case .cloned:
            return .enter(lane)
        case .clonedWithWarnings(let stderr):
            let detail = stderr.isEmpty ? "" : "\n\(stderr)"
            return .enterWithNotice(lane, notice: "Cloned “\(repo.name)” with warnings.\(detail)")
        }
    }
}
