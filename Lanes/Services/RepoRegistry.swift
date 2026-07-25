//
//  RepoRegistry.swift
//  Lanes
//
//  A per-root list of repositories the user has cloned before (or added by
//  hand), kept at `<root>/.lanes/repos.json` so a fresh lane can quickly
//  search-and-clone a repo it needs. Auto-harvested from the repos Lanes
//  discovers in any lane under the root, and manually extendable.
//
//  Entries are deduped by a canonical identity (parsed host/owner/slug, else the
//  normalized raw URL), so the ssh and https forms of one repo collapse into a
//  single entry — keeping the most-recently-seen raw URL for cloning.
//

import Foundation

/// One known repository: the raw `url` is what we clone (ssh vs https preserved),
/// `name` is the display title and default destination folder (the repo slug).
nonisolated struct KnownRepo: Codable, Sendable, Equatable {
    var url: String
    var name: String
    var host: String?
    var owner: String?
    var lastUsedAt: Date
}

nonisolated struct RepoRegistry: Sendable {
    let root: URL

    private var fileURL: URL { LaneFS.repoRegistryURL(in: root) }

    /// All known repos, most-recently-used first (name as a stable tiebreaker).
    func known() -> [KnownRepo] {
        (JSONFile.read([KnownRepo].self, at: fileURL) ?? [])
            .sorted { a, b in
                if a.lastUsedAt != b.lastUsedAt { return a.lastUsedAt > b.lastUsedAt }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    /// Record a repo you actually used (cloned or added by hand): upsert by
    /// canonical identity and **bump `lastUsedAt`** so it sorts to the top.
    func remember(url: String, now: Date = Date()) {
        upsert([url], now: now, bumpRecency: true)
    }

    /// Passively record every URL Lanes discovered (harvest on lane load). Adds
    /// new repos and refreshes a changed remote form, but does **not** bump
    /// recency — so a steady state is a true no-op (no write on every lane load).
    func harvest(_ urls: [String], now: Date = Date()) {
        upsert(urls, now: now, bumpRecency: false)
    }

    /// Remove a repo (by canonical identity) from the list.
    func forget(url: String) {
        guard let repo = Self.makeRepo(url: url, now: Date()) else { return }
        let key = Self.canonicalKey(for: repo)
        let list = (JSONFile.read([KnownRepo].self, at: fileURL) ?? [])
            .filter { Self.canonicalKey(for: $0) != key }
        try? JSONFile.writeAtomic(list, to: fileURL)
    }

    /// Best-effort upsert; writes at most once, only when something changed. An
    /// unparseable URL or a write failure is a no-op (must never break a clone
    /// or a lane load).
    private func upsert(_ urls: [String], now: Date, bumpRecency: Bool) {
        guard !urls.isEmpty else { return }
        var list = JSONFile.read([KnownRepo].self, at: fileURL) ?? []
        var changed = false
        for url in urls {
            guard let repo = Self.makeRepo(url: url, now: now) else { continue }
            let key = Self.canonicalKey(for: repo)
            if let i = list.firstIndex(where: { Self.canonicalKey(for: $0) == key }) {
                var entry = list[i]
                if entry.url != repo.url || entry.name != repo.name
                    || entry.host != repo.host || entry.owner != repo.owner {
                    entry.url = repo.url; entry.name = repo.name
                    entry.host = repo.host; entry.owner = repo.owner
                    changed = true
                }
                if bumpRecency && entry.lastUsedAt != now {
                    entry.lastUsedAt = now
                    changed = true
                }
                list[i] = entry
            } else {
                list.append(repo)
                changed = true
            }
        }
        if changed { try? JSONFile.writeAtomic(list, to: fileURL) }
    }

    // MARK: - Internals

    /// Build a `KnownRepo` from a raw clone URL, parsing host/owner/slug when
    /// possible and otherwise deriving a name from the last path component.
    /// nil when the URL is blank or has no usable name.
    static func makeRepo(url raw: String, now: Date) -> KnownRepo? {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        if let r = GitRemote.parse(url) {
            return KnownRepo(url: url, name: r.slug, host: r.host, owner: r.owner, lastUsedAt: now)
        }
        guard let name = fallbackName(from: url) else { return nil }
        return KnownRepo(url: url, name: name, host: nil, owner: nil, lastUsedAt: now)
    }

    private static func fallbackName(from url: String) -> String? {
        var s = url
        if s.hasSuffix(".git") { s.removeLast(4) }
        let last = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init)
        return (last?.isEmpty == false) ? last : nil
    }

    /// Deduplication identity: parsed host/owner/slug (case-insensitive) when the
    /// URL parsed, else the normalized raw URL.
    static func canonicalKey(for repo: KnownRepo) -> String {
        if let host = repo.host, let owner = repo.owner {
            return "\(host.lowercased())/\(owner.lowercased())/\(repo.name.lowercased())"
        }
        var s = repo.url.lowercased()
        if s.hasSuffix(".git") { s.removeLast(4) }
        return s
    }
}
