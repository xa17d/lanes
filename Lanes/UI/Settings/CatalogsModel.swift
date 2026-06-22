//
//  CatalogsModel.swift
//  Lanes
//
//  Settings-side state for catalogs: the observable model that drives the
//  Catalogs list + config editor, and `ConfigEdits`, the pure filesystem layer
//  that writes/reorders the `.catalog` pointer files those views manage.
//
//  The editor only ever touches Lanes-created pointer files (and the hook /
//  template bindings); hand-made local scripts stay the user's to arrange on
//  disk, so nothing here renames or deletes a file the user wrote.
//

import Foundation
import Combine

// MARK: - Filesystem edits (pure, off-main safe)

nonisolated enum ConfigEdits {
    /// A catalog item available to be referenced — one item *folder* under a
    /// catalog's `script/`, `script/repository/`, `hook/<role>/`, or `template/`,
    /// with its `lanes-item.json` companion (default name/icon + description).
    nonisolated struct Available: Identifiable, Sendable, Hashable {
        let catalog: String       // catalog id
        let item: String          // repo-relative folder path, e.g. "script/open-pr"
        let name: String          // companion name, else the folder name
        let icon: String          // companion icon, else "scroll"
        let detail: String?       // companion description
        var id: String { "\(catalog)/\(item)" }
    }

    /// An enabled pointer entry shown in the editor (parsed from its filename).
    nonisolated struct Entry: Identifiable, Sendable {
        let url: URL
        var order: Int
        var icon: String
        var name: String
        let pointer: Catalogs.Pointer
        var id: String { url.path }
    }

    /// A hand-made local script (not a catalog pointer) in a config dir — shown
    /// read-only in the editor with only "Reveal in Finder".
    nonisolated struct LocalItem: Identifiable, Sendable {
        let url: URL
        let name: String
        let icon: String
        var id: String { url.path }
    }

    /// An enabled, ordered item in a scope — either a catalog pointer or a local
    /// script. Both are reorderable; local ones carry a nil `pointer`.
    nonisolated struct ActiveItem: Identifiable, Sendable {
        let url: URL
        var order: Int
        var icon: String
        var name: String
        let pointer: Catalogs.Pointer?
        let detail: String?
        var isLocal: Bool { pointer == nil }
        var id: String { url.path }
    }

    private static var fm: FileManager { .default }
    private static let defaultIcon = "scroll"

    // MARK: Enumeration

    /// Catalog item folders under `subdir` (e.g. `"script"`,
    /// `"script/repository"`, `"hook/<role>"`, `"template"`) across every
    /// subscribed catalog, each read together with its companion. Skips the
    /// reserved `script/repository` folder when listing lane scripts, and any
    /// dot/README entries.
    static func available(root: URL, subdir: String) -> [Available] {
        Catalogs.list(root: root).flatMap { catalog -> [Available] in
            let dir = catalog.checkout.appendingPathComponent(subdir, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return [] }
            return entries.compactMap { folder -> Available? in
                let leaf = folder.lastPathComponent
                if leaf.hasPrefix(".") || leaf.lowercased().hasPrefix("readme") { return nil }
                if subdir == "script" && leaf == "repository" { return nil }   // reserved
                let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { return nil }
                let meta = Catalogs.itemMeta(at: folder)
                return Available(
                    catalog: catalog.id,
                    item: "\(subdir)/\(leaf)",
                    name: meta?.name?.trimmedNonEmpty ?? leaf,
                    icon: meta?.icon?.trimmedNonEmpty ?? defaultIcon,
                    detail: meta?.description?.trimmedNonEmpty
                )
            }
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Hand-made local executables (not `.catalog` pointers) in `dir`, sorted by
    /// name — shown read-only in the editor.
    static func localItems(in dir: URL) -> [LocalItem] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        let items: [LocalItem] = entries.compactMap { url -> LocalItem? in
            let leaf = url.lastPathComponent
            if leaf.hasPrefix(".") || leaf.lowercased().hasPrefix("readme") { return nil }
            if Catalogs.isPointer(url) { return nil }
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegular, fm.isExecutableFile(atPath: url.path) else { return nil }
            let parsed = parseFilename(url)
            return LocalItem(url: url, name: parsed.name, icon: parsed.icon)
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The `.catalog` pointer entries enabled in `dir`, in display order.
    static func pointers(in dir: URL) -> [Entry] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        let parsed: [Entry] = entries.compactMap { url in
            guard Catalogs.isPointer(url),
                  let pointer = JSONFile.read(Catalogs.Pointer.self, at: url) else { return nil }
            let (order, icon, name) = parseFilename(url)
            return Entry(url: url, order: order, icon: icon, name: name, pointer: pointer)
        }
        return parsed.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            let cmp = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
            return cmp == .orderedAscending
        }
    }

    /// The enabled, ordered items in `dir`: catalog pointers + local scripts
    /// merged and sorted by order, ready to drag-reorder. Catalog items carry
    /// their companion description (resolved against `root`).
    static func activeItems(in dir: URL, root: URL) -> [ActiveItem] {
        var out = pointers(in: dir).map { entry -> ActiveItem in
            let detail = Catalogs.resolveItemFolder(at: entry.url, root: root)
                .flatMap { Catalogs.itemMeta(at: $0)?.description }
            return ActiveItem(url: entry.url, order: entry.order, icon: entry.icon,
                              name: entry.name, pointer: entry.pointer, detail: detail)
        }
        for local in localItems(in: dir) {
            let parsed = parseFilename(local.url)
            out.append(ActiveItem(url: local.url, order: parsed.order, icon: parsed.icon,
                                  name: parsed.name, pointer: nil, detail: nil))
        }
        return out.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: Mutation

    /// Add a pointer to `item` in catalog `catalog` under `dir`, ordered after
    /// every existing active item (catalog pointers + local scripts).
    static func addPointer(in dir: URL, catalog: String, item: String,
                           name: String, icon: String) throws {
        let orders = pointers(in: dir).map(\.order) + localItems(in: dir).map { parseFilename($0.url).order }
        let order = (orders.max() ?? 0) + 10
        let filename = makeFilename(order: order, icon: icon, name: name, ext: Catalogs.pointerExtension)
        try writePointer(Catalogs.Pointer(catalog: catalog, item: item),
                         to: dir.appendingPathComponent(filename))
    }

    /// Rename an active item's file to carry `order`/`icon`/`name`, preserving
    /// its extension — works for both catalog pointers and local scripts.
    @discardableResult
    static func renameActive(_ item: ActiveItem, order: Int, icon: String, name: String) throws -> URL {
        let dir = item.url.deletingLastPathComponent()
        let dest = dir.appendingPathComponent(
            makeFilename(order: order, icon: icon, name: name, ext: item.url.pathExtension))
        if dest != item.url {
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: item.url, to: dest)
        }
        return dest
    }

    /// Persist a new order for `ordered` (after a drag): assign 10, 20, 30… by
    /// renaming each item — catalog pointers and local scripts alike.
    static func applyOrder(_ ordered: [ActiveItem]) {
        for (index, item) in ordered.enumerated() {
            _ = try? renameActive(item, order: (index + 1) * 10, icon: item.icon, name: item.name)
        }
    }

    static func remove(_ url: URL) throws {
        try fm.removeItem(at: url)
    }

    /// Remove the pointer(s) in `dir` that reference catalog `catalog`'s `item`
    /// (used to deactivate a catalog item via its checkbox).
    static func removePointer(catalog: String, item: String, in dir: URL) {
        for entry in pointers(in: dir)
        where entry.pointer.catalog == catalog && entry.pointer.item == item {
            try? fm.removeItem(at: entry.url)
        }
    }

    /// Enable one catalog item (writing a pointer seeded from its companion), but
    /// only if it actually exists in the checkout — so a renamed/removed item is
    /// silently skipped.
    static func enable(catalog id: String, item: String, in dir: URL, root: URL) {
        let folder = LaneFS.catalogCheckout(id: id, in: root).appendingPathComponent(item)
        guard fm.fileExists(atPath: folder.path) else { return }
        let meta = Catalogs.itemMeta(at: folder)
        let name = meta?.name?.trimmedNonEmpty ?? (item as NSString).lastPathComponent
        try? addPointer(in: dir, catalog: id, item: item,
                        name: name, icon: meta?.icon?.trimmedNonEmpty ?? defaultIcon)
    }

    /// Enable a small curated starter set from the default catalog, so the
    /// launcher is useful immediately after auto-subscribing.
    static func enableStarterSet(catalog id: String, root: URL) {
        let lane = LaneFS.scriptDir(in: root)
        let repo = LaneFS.repoScriptDir(in: root)
        for item in ["script/open-terminal", "script/claude"] {
            enable(catalog: id, item: item, in: lane, root: root)
        }
        for item in ["script/repository/open-pr", "script/repository/open-terminal",
                     "script/repository/copy-branch", "script/repository/open-repo-in-browser"] {
            enable(catalog: id, item: item, in: repo, root: root)
        }
    }

    // MARK: Hooks & template bindings

    /// The pointer bound to hook `name`, if any.
    static func hookPointer(_ name: String, root: URL) -> Catalogs.Pointer? {
        JSONFile.read(Catalogs.Pointer.self, at: hookPointerURL(name, root: root))
    }

    /// Whether a local (non-pointer) executable hook named `name` exists.
    static func hasLocalHook(_ name: String, root: URL) -> Bool {
        let url = LaneFS.hookDir(in: root).appendingPathComponent(name)
        let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        return isRegular && fm.isExecutableFile(atPath: url.path)
    }

    static func setHookPointer(_ name: String, catalog: String, item: String, root: URL) throws {
        try writePointer(Catalogs.Pointer(catalog: catalog, item: item),
                         to: hookPointerURL(name, root: root))
    }

    static func clearHookPointer(_ name: String, root: URL) throws {
        let url = hookPointerURL(name, root: root)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    /// The pointer bound to the new-lane template, if any.
    static func templatePointer(root: URL) -> Catalogs.Pointer? {
        JSONFile.read(Catalogs.Pointer.self, at: LaneFS.templatePointer(in: root))
    }

    static func setTemplatePointer(catalog: String, item: String, root: URL) throws {
        try writePointer(Catalogs.Pointer(catalog: catalog, item: item),
                         to: LaneFS.templatePointer(in: root))
    }

    static func clearTemplatePointer(root: URL) throws {
        let url = LaneFS.templatePointer(in: root)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    // MARK: Internals

    private static func hookPointerURL(_ name: String, root: URL) -> URL {
        LaneFS.hookDir(in: root).appendingPathComponent("\(name).\(Catalogs.pointerExtension)")
    }

    private static func writePointer(_ pointer: Catalogs.Pointer, to url: URL) throws {
        try JSONFile.writeAtomic(pointer, to: url)
    }

    private static func makeFilename(order: Int, icon: String, name: String, ext: String) -> String {
        let safeIcon = icon.trimmingCharacters(in: .whitespaces).isEmpty ? defaultIcon : icon
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let base = "\(order)---\(safeIcon)---\(safeName)"
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// `<order>---<icon>---<name>.catalog` → (order, icon, name); mirrors
    /// `ScriptItems.parse` for the display fields.
    private static func parseFilename(_ url: URL) -> (order: Int, icon: String, name: String) {
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        let parts = base.components(separatedBy: "---")
        guard parts.count >= 3 else { return (0, defaultIcon, base) }
        let order = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
        let icon = parts[1].trimmingCharacters(in: .whitespaces)
        let name = parts[2...].joined(separator: "---").trimmingCharacters(in: .whitespaces)
        return (order, icon.isEmpty ? defaultIcon : icon, name.isEmpty ? base : name)
    }
}

private extension String {
    /// The string trimmed of surrounding whitespace, or nil when that's empty.
    nonisolated var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Observable model

@MainActor
final class CatalogsModel: ObservableObject {
    @Published private(set) var catalogs: [Catalogs.Loaded] = []
    @Published private(set) var busy = false
    @Published var errorMessage: String?

    private let library: LaneLibrary
    private let shell = Shell()

    init(library: LaneLibrary) {
        self.library = library
        reload()
    }

    var root: URL? { library.root }
    var hasUpdates: Bool { catalogs.contains(where: \.hasUpdate) }

    /// Human-facing name for a catalog id (from its manifest), falling back to
    /// the id when the catalog isn't loaded.
    func name(for id: String) -> String {
        catalogs.first { $0.id == id }?.name ?? id
    }

    /// Whether the one-time "running catalog code" warning has been acknowledged.
    static var trustAcknowledged: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKeys.catalogTrustAcknowledged) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKeys.catalogTrustAcknowledged) }
    }

    func reload() {
        guard let root else { catalogs = []; return }
        catalogs = Catalogs.list(root: root)
    }

    func add(url: String, ref: String) {
        run { root in try Catalogs.add(url: url, ref: ref, root: root, shell: self.shell) }
    }

    /// Subscribe to the official default catalog and enable a starter set (the
    /// empty-state "Add default catalog" button).
    func addDefault() {
        run { root in
            try Catalogs.add(url: Catalogs.defaultURL, ref: "", root: root, shell: self.shell)
            if let id = Catalogs.id(forURL: Catalogs.defaultURL) {
                ConfigEdits.enableStarterSet(catalog: id, root: root)
            }
        }
    }

    /// UserDefaults key: roots we've already auto-subscribed the default catalog
    /// for (so removing it isn't undone on the next launch).
    private static let seededRootsKey = "defaultCatalogSeededRoots"

    /// On the first sighting of `root`, silently subscribe to the default catalog
    /// and enable a starter set. Gated so it runs once per root; a clone failure
    /// (e.g. offline) leaves it unseeded to retry next launch. `onChange` runs on
    /// the main actor after a successful seed.
    @MainActor
    static func seedDefaultIfNeeded(root: URL, onChange: @escaping @MainActor () -> Void) {
        let defaults = UserDefaults.standard
        var seeded = Set(defaults.stringArray(forKey: seededRootsKey) ?? [])
        guard !seeded.contains(root.path), let id = Catalogs.id(forURL: Catalogs.defaultURL) else { return }
        // Already present (e.g. added manually) → mark seeded, don't duplicate.
        if Catalogs.config(id: id, root: root) != nil {
            seeded.insert(root.path)
            defaults.set(Array(seeded), forKey: seededRootsKey)
            return
        }
        Task.detached {
            do {
                try Catalogs.add(url: Catalogs.defaultURL, ref: "", root: root, shell: Shell())
                ConfigEdits.enableStarterSet(catalog: id, root: root)
            } catch {
                return   // leave unseeded so it retries next launch
            }
            await MainActor.run {
                let store = UserDefaults.standard
                var s = Set(store.stringArray(forKey: Self.seededRootsKey) ?? [])
                s.insert(root.path)
                store.set(Array(s), forKey: Self.seededRootsKey)
                onChange()
            }
        }
    }

    func syncAll() {
        run { root in Catalogs.fetchAllIfStale(root: root, shell: self.shell, maxAge: 0) }
    }

    func apply(_ id: String) {
        run { root in try Catalogs.apply(id: id, root: root, shell: self.shell) }
    }

    func remove(_ id: String) {
        run { root in try Catalogs.remove(id: id, root: root) }
    }

    /// Run a filesystem/git operation off-main, then reload on main.
    private func run(_ work: @escaping @Sendable (URL) throws -> Void) {
        guard let root else { return }
        busy = true
        errorMessage = nil
        Task.detached {
            var failure: String?
            do { try work(root) } catch { failure = error.localizedDescription }
            await MainActor.run {
                self.busy = false
                if let failure { self.errorMessage = failure }
                self.reload()
                // Update availability changed (applied/added/removed/synced) — keep
                // the menu-bar dot + lane-list banner in sync.
                AppCore.shared.model.refreshCatalogIndicator()
            }
        }
    }
}
