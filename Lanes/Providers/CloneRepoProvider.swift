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
//  The search field doubles as a URL field: a query that matches no known repo
//  but parses as a clone URL becomes a "Clone <repo>" action (via the level's
//  queryFallback), so the list fills itself purely from what you actually clone.
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
            subtitle: "Search a known repo, or paste a clone URL",
            icon: .repo,
            keywords: ["clone", "repo", "git", "checkout"],
            childrenProvider: {
                // Read the registry live so a freshly cloned repo shows up when
                // this level is reloaded.
                registry.known().map { repo in
                    Self.repoItem(repo, lane: lane, root: root, cloner: cloner, registry: registry)
                }
            },
            // The search field doubles as a URL field: an unmatched query that
            // looks like a clone target (a URL or path — not a bare-word typo)
            // becomes a one-shot "Clone <repo>" action.
            queryFallback: { raw in
                let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard Self.looksLikeCloneTarget(q),
                      let repo = RepoRegistry.makeRepo(url: q, now: Date()) else { return nil }
                return BasicItem(
                    id: "clone:url",
                    title: "Clone \(repo.name)",
                    subtitle: q,
                    icon: .add,
                    keywords: ["clone", "url"],
                    run: { try Self.performClone(repo, lane: lane, root: root, cloner: cloner, registry: registry) }
                )
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

    /// Whether a query looks like something to clone (a URL or a path) rather
    /// than a bare-word repo-name search that simply didn't match — so a typo
    /// like "widgt" never becomes a clone offer, but `git@…`, `https://…`,
    /// `host:owner/repo`, and `/local/path` do.
    static func looksLikeCloneTarget(_ q: String) -> Bool {
        guard !q.isEmpty else { return false }
        return q.contains("/") || q.contains(":") || q.contains("@")
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
