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
    static let archiveDirName = ".archive"
    static let metaKey = "lane"

    private static var fm: FileManager { .default }

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
        let meta = LaneMeta(id: UUID(), createdAt: Date(), lastOpenedAt: nil)
        try JSONFile.writeAtomic(meta, to: url)
        return meta
    }

    private static func lane(at url: URL) throws -> Lane {
        let meta = try loadOrCreateMeta(at: url)
        return Lane(url: url, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: meta.lastOpenedAt)
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
            let archive = root.appendingPathComponent(archiveDirName, isDirectory: true)
            urls += childDirectories(of: archive)
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
        let meta = LaneMeta(id: UUID(), createdAt: Date(), lastOpenedAt: nil)
        try JSONFile.writeAtomic(meta, to: metaURL(for: dest))
        return Lane(url: dest, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: nil)
    }

    @discardableResult
    static func touch(_ lane: Lane, now: Date = Date()) throws -> Lane {
        var meta = try loadOrCreateMeta(at: lane.url)
        meta.lastOpenedAt = now
        try JSONFile.writeAtomic(meta, to: metaURL(for: lane.url))
        return Lane(url: lane.url, id: meta.id, createdAt: meta.createdAt, lastOpenedAt: now)
    }

    static func archive(_ lane: Lane, in root: URL) throws -> Lane {
        let archiveDir = root.appendingPathComponent(archiveDirName, isDirectory: true)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: archiveDir, base: lane.name)
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
