//
//  LaneFS.swift
//  lane
//
//  Pure filesystem operations behind LaneLibrary. Foundation-only and
//  isolation-free so the rules (discovery, atomic meta, archive collisions,
//  rename-keeps-id) can be unit-tested directly.
//

import Foundation

nonisolated enum LaneFSError: LocalizedError {
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name): return "“\(name)” already exists."
        }
    }
}

nonisolated enum LaneFS {
    /// The single dotfolder under the root that holds all of Lanes' own state:
    /// `archive/` (archived lanes) and `config/template/` (new-lane template).
    static let lanesDirName = ".lanes"
    /// Archived lanes live under `<root>/.lanes/archive/` (no leading dot — the
    /// `.lanes` parent already hides the whole tree).
    static let archiveDirName = "archive"
    static let metaKey = "lane"

    private static var fm: FileManager { .default }

    // MARK: - Well-known locations

    static func lanesDir(in root: URL) -> URL {
        root.appendingPathComponent(lanesDirName, isDirectory: true)
    }

    static func archiveDir(in root: URL) -> URL {
        lanesDir(in: root).appendingPathComponent(archiveDirName, isDirectory: true)
    }

    private static func configDir(in root: URL) -> URL {
        lanesDir(in: root).appendingPathComponent("config", isDirectory: true)
    }

    /// `<root>/.lanes/config/template` — its contents seed every new lane.
    static func templateDir(in root: URL) -> URL {
        configDir(in: root).appendingPathComponent("template", isDirectory: true)
    }

    /// `<root>/.lanes/config/script-items` — each executable file is a custom
    /// lane-level action (run with the lane dir as cwd).
    static func scriptItemsDir(in root: URL) -> URL {
        configDir(in: root).appendingPathComponent("script-items", isDirectory: true)
    }

    /// `<root>/.lanes/config/script-items/repository` — each executable file is
    /// a custom per-repository action (run with the repo dir as cwd).
    static func repoScriptItemsDir(in root: URL) -> URL {
        scriptItemsDir(in: root).appendingPathComponent("repository", isDirectory: true)
    }

    /// `<root>/.lanes/config/hooks` — lifecycle hook scripts (e.g.
    /// `update-lane-description`).
    static func hooksDir(in root: URL) -> URL {
        configDir(in: root).appendingPathComponent("hooks", isDirectory: true)
    }

    // MARK: - Meta

    private static func metaURL(for laneURL: URL) -> URL {
        laneURL
            .appendingPathComponent(".lane", isDirectory: true)
            .appendingPathComponent("\(metaKey).json")
    }

    /// Load a lane's meta, creating `lane.json` (new UUID, createdAt now) if
    /// it is missing.
    static func loadOrCreateMeta(at laneURL: URL) throws -> LaneMeta {
        let url = metaURL(for: laneURL)
        if let meta = JSONFile.read(LaneMeta.self, at: url) {
            return meta
        }
        let meta = LaneMeta(id: UUID(), createdAt: Date(), lastOpenedAt: nil, summary: nil)
        try JSONFile.writeAtomic(meta, to: url)
        // The folder becomes a lane the moment its meta is first written —
        // whether we just created it or adopted an externally-made folder on
        // scan. Either way, seed it from the template here so both paths share
        // exactly one code path.
        applyTemplateIfPresent(to: laneURL)
        return meta
    }

    private static func lane(at url: URL) throws -> Lane {
        let meta = try loadOrCreateMeta(at: url)
        return Lane(url: url, id: meta.id, createdAt: meta.createdAt,
                    lastOpenedAt: meta.lastOpenedAt, summary: meta.summary)
    }

    // MARK: - Listing

    private static func childDirectories(of dir: URL) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            // skip dotfiles (belt-and-suspenders with skipsHiddenFiles) and
            // non-directories
            !url.lastPathComponent.hasPrefix(".")
                && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    /// All lanes in `root`, sorted by lastOpenedAt desc (nil last), then name.
    static func lanes(in root: URL, includeArchived: Bool = false) -> [Lane] {
        var urls = childDirectories(of: root)
        if includeArchived {
            urls += childDirectories(of: archiveDir(in: root))
        }
        let loaded = urls.compactMap { try? lane(at: $0) }
        return loaded.sorted { a, b in
            switch (a.lastOpenedAt, b.lastOpenedAt) {
            case let (x?, y?): return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    // MARK: - Mutations

    static func create(name: String, in root: URL) throws -> Lane {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent(name, isDirectory: true)
        guard !fm.fileExists(atPath: dest.path) else { throw LaneFSError.alreadyExists(name) }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        // Go through loadOrCreateMeta (via lane(at:)) so creation and external
        // adoption share the same meta-write + template-seeding logic.
        return try lane(at: dest)
    }

    @discardableResult
    static func touch(_ lane: Lane, now: Date = Date()) throws -> Lane {
        var meta = try loadOrCreateMeta(at: lane.url)
        meta.lastOpenedAt = now
        try JSONFile.writeAtomic(meta, to: metaURL(for: lane.url))
        return Lane(url: lane.url, id: meta.id, createdAt: meta.createdAt,
                    lastOpenedAt: now, summary: meta.summary)
    }

    /// Set (or clear) the lane's one-line description. Returns the updated lane.
    static func setSummary(_ lane: Lane, to summary: String) throws -> Lane {
        var meta = try loadOrCreateMeta(at: lane.url)
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.summary = trimmed.isEmpty ? nil : trimmed
        try JSONFile.writeAtomic(meta, to: metaURL(for: lane.url))
        return Lane(url: lane.url, id: meta.id, createdAt: meta.createdAt,
                    lastOpenedAt: meta.lastOpenedAt, summary: meta.summary)
    }

    static func archive(_ lane: Lane, in root: URL) throws -> Lane {
        let dir = archiveDir(in: root)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: dir, base: lane.name)
        try fm.moveItem(at: lane.url, to: dest)
        return try self.lane(at: dest)
    }

    static func unarchive(_ lane: Lane, in root: URL) throws -> Lane {
        let dest = uniqueDestination(in: root, base: lane.name)
        try fm.moveItem(at: lane.url, to: dest)
        return try self.lane(at: dest)
    }

    static func rename(_ lane: Lane, to name: String) throws -> Lane {
        let parent = lane.url.deletingLastPathComponent()
        let dest = parent.appendingPathComponent(name, isDirectory: true)
        guard !fm.fileExists(atPath: dest.path) else { throw LaneFSError.alreadyExists(name) }
        try fm.moveItem(at: lane.url, to: dest)
        // id in lane.json keeps identity; reload at the new url.
        return try self.lane(at: dest)
    }

    static func delete(_ lane: Lane) throws {
        try fm.removeItem(at: lane.url)
    }

    // MARK: - Helpers

    /// Copy the contents of `<root>/.lanes/config/template` into a freshly
    /// minted lane. The root is the lane's parent (active lanes sit directly
    /// under the root). No-op when there is no template. Existing entries in the
    /// lane (e.g. the `.lane` meta we just wrote) are never clobbered.
    private static func applyTemplateIfPresent(to laneURL: URL) {
        let template = templateDir(in: laneURL.deletingLastPathComponent())
        guard let entries = try? fm.contentsOfDirectory(
            at: template, includingPropertiesForKeys: nil, options: []
        ) else { return }
        for entry in entries {
            let dest = laneURL.appendingPathComponent(entry.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.copyItem(at: entry, to: dest)
        }
    }

    /// First of `base`, `base-2`, `base-3`, … that does not exist in `dir`.
    private static func uniqueDestination(in dir: URL, base: String) -> URL {
        let first = dir.appendingPathComponent(base, isDirectory: true)
        if !fm.fileExists(atPath: first.path) { return first }
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base)-\(n)", isDirectory: true)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
