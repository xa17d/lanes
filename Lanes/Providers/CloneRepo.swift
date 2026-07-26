//
//  CloneRepo.swift
//  Lanes
//
//  A single "Clone repo…" container whose children are the root's known repos
//  (RepoRegistry), so from inside a lane you can search a repo you cloned before
//  and clone it here. It lives under "Manage lane…" (built by LaneActions), not
//  as a top-level provider, so the lane's top level holds only actual content.
//  Because SubtreeIndex indexes descendants, the repos stay reachable by name
//  from the lane's top level even nested one level deeper.
//
//  Picking a repo (or the query fallback below) returns `.startClone`, which
//  LaneModel runs as a background clone: the panel returns to the lane and shows
//  a spinner row until the clone finishes, so several can run at once without
//  blocking. The search field doubles as a URL field: a query that matches no
//  known repo but looks like a clone target becomes a "Clone <repo>" action.
//  The list fills itself from what you actually clone (LaneModel remembers it).
//

import Foundation

nonisolated enum CloneRepo {
    /// The "Clone repo…" container for a lane, built from the root's known-repo
    /// registry. Composed into "Manage lane…" (see `LaneActions`).
    static func container(for lane: Lane) -> any Item {
        let root = LaneActions.root(of: lane)
        let registry = RepoRegistry(root: root)

        return BasicItem(
            id: "clone:container",
            title: "Clone repo…",
            subtitle: "Search a known repo, or paste a clone URL (⇧Return queues several)",
            icon: .clone,
            keywords: ["clone", "repo", "git", "checkout"],
            isSecondary: true,
            childrenProvider: {
                // Read the registry live so a freshly cloned repo shows up when
                // this level is reloaded.
                registry.known().map { repoItem($0, lane: lane) }
            },
            // The search field doubles as a URL field: an unmatched query that
            // looks like a clone target (a URL or path — not a bare-word typo)
            // becomes a one-shot "Clone <repo>" action.
            queryFallback: { raw in
                let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard looksLikeCloneTarget(q),
                      let repo = RepoRegistry.makeRepo(url: q, now: Date()) else { return nil }
                return BasicItem(
                    id: "clone:url",
                    title: "Clone \(repo.name)",
                    subtitle: q,
                    icon: .add,
                    keywords: ["clone", "url"],
                    run: { .startClone(lane: lane, url: repo.url) }
                )
            }
        )
    }

    // MARK: - Items

    private static func repoItem(_ repo: KnownRepo, lane: Lane) -> any Item {
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
            run: { .startClone(lane: lane, url: repo.url) }
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
}
