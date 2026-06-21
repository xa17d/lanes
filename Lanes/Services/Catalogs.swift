//
//  Catalogs.swift
//  Lanes
//
//  Catalogs are git repositories of shared config (scripts, hooks, templates)
//  that a root subscribes to. Each catalog lives under
//  `<root>/.lanes/catalog/<id>/` as:
//
//    catalog.json   — the descriptor { url, ref, pin, lastFetchedAt, latest }
//    checkout/      — the git clone (a rebuildable cache; the descriptor is truth)
//
//  Local config references a catalog item through a thin `.catalog` pointer file
//  (`{ "catalog": "<id>", "item": "script/deploy.sh" }`); the pointer's own
//  filename supplies the display order/icon/name, the JSON only locates content.
//
//  Two layers, kept separate so callers without a Shell (e.g. template seeding)
//  can still resolve pointers:
//    - pure resolution (`resolvePointer`, `list`, `config`) needs only the
//      filesystem;
//    - the git lifecycle (`add`/`fetch`/`apply`/`remove`) needs a `Shell`.
//

import Foundation

nonisolated enum CatalogError: LocalizedError {
    case invalidURL(String)
    case notACatalog(String)
    case notFound(String)
    case gitFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "“\(url)” isn’t a recognizable git URL."
        case .notACatalog(let url):
            return "“\(url)” isn’t a Lanes catalog (it needs a lanes-catalog.json with a name at its root)."
        case .notFound(let id): return "Catalog “\(id)” not found."
        case .gitFailed(let msg): return msg
        }
    }
}

nonisolated enum Catalogs {
    /// Extension of a pointer file that references a catalog item.
    static let pointerExtension = "catalog"

    private static let gitPath = "/usr/bin/git"
    private static var fm: FileManager { .default }

    /// The persisted descriptor. `pin` is the applied commit (what lanes run);
    /// `latest`/`lastFetchedAt` are fetch state — `latest != pin` means an update
    /// is available but not yet applied.
    nonisolated struct Config: Codable, Sendable {
        var url: String
        var ref: String
        var pin: String
        var lastFetchedAt: Date?
        var latest: String?
    }

    /// A loaded catalog: its id (the folder name), descriptor, owning root, and
    /// the human-facing name from the catalog's `lanes-catalog.json` manifest.
    nonisolated struct Loaded: Sendable, Identifiable {
        let id: String
        let config: Config
        let root: URL
        let name: String
        var checkout: URL { LaneFS.catalogCheckout(id: id, in: root) }
        var hasUpdate: Bool {
            guard let latest = config.latest else { return false }
            return latest != config.pin
        }
    }

    /// The body of a `.catalog` pointer file.
    nonisolated struct Pointer: Codable, Sendable {
        let catalog: String
        let item: String
    }

    /// `lanes-catalog.json` at a catalog repo's root — required, and the source
    /// of the human-facing name shown instead of the folder id.
    nonisolated struct Manifest: Codable, Sendable {
        var name: String
    }

    static let manifestFilename = "lanes-catalog.json"

    /// Read a catalog's `lanes-catalog.json` manifest from its checkout.
    static func manifest(forCheckout checkout: URL) -> Manifest? {
        JSONFile.read(Manifest.self, at: checkout.appendingPathComponent(manifestFilename))
    }

    // MARK: - Identity

    /// Stable, filesystem-safe on-disk id for a git URL. Recognizable remotes
    /// become `<host>_<owner>_<slug>`; anything else (ssh aliases, local paths)
    /// falls back to a sanitized slug of the URL. nil only for an empty URL.
    static func id(forURL raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let remote = GitRemote.parse(trimmed) {
            let owner = remote.owner.replacingOccurrences(of: "/", with: "_")
            return "\(remote.host)_\(owner)_\(remote.slug)"
        }
        var slug = trimmed
        if slug.hasSuffix(".git") { slug.removeLast(4) }
        let mapped = slug.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "." || ch == "-" ? ch : "_"
        }
        let collapsed = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? nil : collapsed
    }

    // MARK: - Pure resolution (no Shell)

    /// Whether `url` is a `.catalog` pointer file (by extension).
    static func isPointer(_ url: URL) -> Bool {
        url.pathExtension == pointerExtension
    }

    /// Resolve a `.catalog` pointer to the target path inside its catalog's
    /// checkout, or nil when the pointer/catalog/item is missing or invalid.
    static func resolvePointer(at url: URL, root: URL) -> URL? {
        guard let pointer = JSONFile.read(Pointer.self, at: url) else { return nil }
        let target = LaneFS.catalogCheckout(id: pointer.catalog, in: root)
            .appendingPathComponent(pointer.item)
        return fm.fileExists(atPath: target.path) ? target : nil
    }

    /// Read one catalog's descriptor.
    static func config(id: String, root: URL) -> Config? {
        JSONFile.read(Config.self, at: LaneFS.catalogConfigURL(id: id, in: root))
    }

    /// All subscribed catalogs (sorted by id), each as a `Loaded`.
    static func list(root: URL) -> [Loaded] {
        let dir = LaneFS.catalogDir(in: root)
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { sub -> Loaded? in
            let isDir = (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let id = sub.lastPathComponent
            guard isDir, let cfg = config(id: id, root: root) else { return nil }
            let name = manifest(forCheckout: LaneFS.catalogCheckout(id: id, in: root))?.name ?? id
            return Loaded(id: id, config: cfg, root: root, name: name)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// True when any subscribed catalog has fetched an update that isn't applied.
    static func anyUpdatesAvailable(root: URL) -> Bool {
        list(root: root).contains { $0.hasUpdate }
    }

    // MARK: - Git lifecycle (needs a Shell)

    /// Subscribe to a catalog: clone it, check out `ref` (blank = the clone's
    /// default branch), and write the descriptor pinned to the resolved commit.
    static func add(url: String, ref: String, root: URL, shell: Shell) throws {
        guard let id = id(forURL: url) else { throw CatalogError.invalidURL(url) }
        let dir = LaneFS.catalogDir(id: id, in: root)
        let checkout = LaneFS.catalogCheckout(id: id, in: root)
        if fm.fileExists(atPath: checkout.path) { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        try git(["clone", "--", url, checkout.path], shell: shell)
        let trimmedRef = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRef.isEmpty {
            try git(["-C", checkout.path, "checkout", "--force", trimmedRef], shell: shell)
        }
        // A catalog must declare itself with a named lanes-catalog.json manifest.
        guard let name = manifest(forCheckout: checkout)?.name
            .trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            try? fm.removeItem(at: dir)
            throw CatalogError.notACatalog(url)
        }
        let resolvedRef = trimmedRef.isEmpty
            ? (revParse(checkout, "--abbrev-ref", "HEAD", shell: shell) ?? "main")
            : trimmedRef
        guard let pin = revParse(checkout, "HEAD", shell: shell) else {
            try? fm.removeItem(at: dir)
            throw CatalogError.gitFailed("Could not resolve HEAD after cloning \(url).")
        }
        let cfg = Config(url: url, ref: resolvedRef, pin: pin, lastFetchedAt: Date(), latest: pin)
        try JSONFile.writeAtomic(cfg, to: LaneFS.catalogConfigURL(id: id, in: root))
    }

    /// Fetch (no checkout change): refresh remote refs/tags and record the commit
    /// that `ref` now resolves to. Returns whether an update is now available.
    @discardableResult
    static func fetch(id: String, root: URL, shell: Shell) throws -> Bool {
        guard var cfg = config(id: id, root: root) else { throw CatalogError.notFound(id) }
        let checkout = LaneFS.catalogCheckout(id: id, in: root)
        try git(["-C", checkout.path, "fetch", "--tags", "--force", "origin"], shell: shell)
        let latest = revParse(checkout, "origin/\(cfg.ref)", shell: shell)
            ?? revParse(checkout, cfg.ref, shell: shell)
            ?? cfg.pin
        cfg.latest = latest
        cfg.lastFetchedAt = Date()
        try JSONFile.writeAtomic(cfg, to: LaneFS.catalogConfigURL(id: id, in: root))
        return latest != cfg.pin
    }

    /// Fetch every catalog whose last fetch is older than `maxAge` (default 1
    /// day). Network failures are swallowed so a down remote never blocks.
    static func fetchAllIfStale(root: URL, shell: Shell, maxAge: TimeInterval = 24 * 60 * 60) {
        let now = Date()
        for catalog in list(root: root) {
            if let last = catalog.config.lastFetchedAt, now.timeIntervalSince(last) < maxAge { continue }
            _ = try? fetch(id: catalog.id, root: root, shell: shell)
        }
    }

    /// Apply the fetched update: check the working tree out to `latest` and
    /// advance the pin. This is the only operation that changes what lanes run.
    static func apply(id: String, root: URL, shell: Shell) throws {
        guard var cfg = config(id: id, root: root) else { throw CatalogError.notFound(id) }
        let target = cfg.latest ?? cfg.pin
        let checkout = LaneFS.catalogCheckout(id: id, in: root)
        try git(["-C", checkout.path, "checkout", "--force", target], shell: shell)
        cfg.pin = target
        try JSONFile.writeAtomic(cfg, to: LaneFS.catalogConfigURL(id: id, in: root))
    }

    /// Unsubscribe: delete the catalog (descriptor + checkout). Existing pointer
    /// files referencing it simply stop resolving.
    static func remove(id: String, root: URL) throws {
        try fm.removeItem(at: LaneFS.catalogDir(id: id, in: root))
    }

    // MARK: - Internals

    @discardableResult
    private static func git(_ args: [String], shell: Shell) throws -> String {
        do {
            return try shell.run(gitPath, args, env: ["GIT_TERMINAL_PROMPT": "0"])
        } catch let error as ShellError {
            throw CatalogError.gitFailed(error.localizedDescription)
        }
    }

    private static func revParse(_ checkout: URL, _ args: String..., shell: Shell) -> String? {
        let out = try? shell.run(gitPath, ["-C", checkout.path, "rev-parse"] + args,
                                 env: ["GIT_TERMINAL_PROMPT": "0"])
        let trimmed = out?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
