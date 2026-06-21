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
    /// A catalog item available to be referenced (one file under a catalog's
    /// `script/`, `script/repository/`, or `hook/`).
    nonisolated struct Available: Identifiable, Sendable, Hashable {
        let catalog: String      // catalog id
        let item: String         // repo-relative path, e.g. "script/deploy.sh"
        var name: String { ((item as NSString).lastPathComponent as NSString).deletingPathExtension }
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

    private static var fm: FileManager { .default }
    private static let defaultIcon = "scroll"

    // MARK: Enumeration

    /// Catalog items under `subdir` (e.g. `"script"`, `"script/repository"`,
    /// `"hook"`) across every subscribed catalog. Skips dot/README files and
    /// sub-directories.
    static func available(root: URL, subdir: String) -> [Available] {
        Catalogs.list(root: root).flatMap { catalog -> [Available] in
            let dir = catalog.checkout.appendingPathComponent(subdir, isDirectory: true)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) else { return [] }
            return entries.compactMap { url in
                let name = url.lastPathComponent
                if name.hasPrefix(".") || name.lowercased().hasPrefix("readme") { return nil }
                let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isRegular else { return nil }
                return Available(catalog: catalog.id, item: "\(subdir)/\(name)")
            }
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Catalog ids that ship a `template/` directory.
    static func availableTemplates(root: URL) -> [String] {
        Catalogs.list(root: root).compactMap { catalog in
            let dir = catalog.checkout.appendingPathComponent("template", isDirectory: true)
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? catalog.id : nil
        }
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

    // MARK: Mutation

    /// Add a pointer to `item` in catalog `catalog` under `dir`, ordered after
    /// any existing entries.
    static func addPointer(in dir: URL, catalog: String, item: String,
                           name: String, icon: String) throws {
        let order = (pointers(in: dir).map(\.order).max() ?? 0) + 10
        let filename = makeFilename(order: order, icon: icon, name: name)
        try writePointer(Catalogs.Pointer(catalog: catalog, item: item),
                         to: dir.appendingPathComponent(filename))
    }

    /// Rewrite a pointer's display fields (order/icon/name) by renaming it,
    /// preserving its target. Returns the new URL.
    @discardableResult
    static func updatePointer(_ entry: Entry, order: Int, icon: String, name: String) throws -> URL {
        let dir = entry.url.deletingLastPathComponent()
        let dest = dir.appendingPathComponent(makeFilename(order: order, icon: icon, name: name))
        if dest != entry.url {
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: entry.url, to: dest)
        }
        return dest
    }

    /// Persist a new order for `ordered` (e.g. after a drag/move): assign
    /// 10, 20, 30… by renaming each pointer.
    static func applyOrder(_ ordered: [Entry]) throws {
        for (index, entry) in ordered.enumerated() {
            _ = try updatePointer(entry, order: (index + 1) * 10, icon: entry.icon, name: entry.name)
        }
    }

    static func remove(_ url: URL) throws {
        try fm.removeItem(at: url)
    }

    // MARK: Hooks & template bindings

    /// The pointer bound to hook `name`, if any.
    static func hookPointer(_ name: String, root: URL) -> Catalogs.Pointer? {
        JSONFile.read(Catalogs.Pointer.self, at: hookPointerURL(name, root: root))
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

    static func setTemplatePointer(catalog: String, root: URL) throws {
        try writePointer(Catalogs.Pointer(catalog: catalog, item: "template"),
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

    private static func makeFilename(order: Int, icon: String, name: String) -> String {
        let safeIcon = icon.trimmingCharacters(in: .whitespaces).isEmpty ? defaultIcon : icon
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        return "\(order)---\(safeIcon)---\(safeName).\(Catalogs.pointerExtension)"
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
            }
        }
    }
}
