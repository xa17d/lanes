//
//  CatalogSettingsView.swift
//  Lanes
//
//  Settings UI for catalogs: subscribe/sync/apply/remove shared config repos
//  (Catalogs tab), enable/order catalog items vs local scripts (Items tab), and
//  bind hooks + the new-lane template to catalog content (Hooks tab).
//

import SwiftUI

// MARK: - Catalogs list

struct CatalogsSection: View {
    @ObservedObject var model: CatalogsModel
    @State private var showAdd = false
    @State private var showTrust = false
    @State private var pendingURL = ""
    @State private var pendingRef = ""

    var body: some View {
        Section("Catalogs") {
            if model.catalogs.isEmpty {
                Text("Subscribe to a git repo of shared scripts, hooks, and templates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Add the default catalog (recommended)") { model.addDefault() }
                    .disabled(model.busy)
            }
            ForEach(model.catalogs) { catalog in
                CatalogRow(catalog: catalog,
                           onApply: { model.apply(catalog.id) },
                           onRemove: { model.remove(catalog.id) })
            }
            HStack {
                Button("Add Catalog…") { showAdd = true }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Sync Now") { model.syncAll() }
                    .disabled(model.catalogs.isEmpty || model.busy)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddCatalogSheet(url: $pendingURL, ref: $pendingRef) {
                if CatalogsModel.trustAcknowledged {
                    commitAdd()
                } else {
                    showTrust = true
                }
            }
        }
        .alert("Catalogs run shared code on your Mac", isPresented: $showTrust) {
            Button("Cancel", role: .cancel) {}
            Button("I understand, add it") {
                CatalogsModel.trustAcknowledged = true
                commitAdd()
            }
        } message: {
            Text("A catalog's scripts, hooks, and template run on your machine with your "
                 + "environment — and applying an update runs newly-fetched code. Only add "
                 + "catalogs from people you trust.")
        }
    }

    private func commitAdd() {
        let url = pendingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        model.add(url: url, ref: pendingRef)
        pendingURL = ""
        pendingRef = ""
    }
}

private struct CatalogRow: View {
    let catalog: Catalogs.Loaded
    let onApply: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(catalog.name).font(.system(size: 12, weight: .medium))
                Text("\(catalog.config.url) · \(catalog.config.ref) · \(String(catalog.config.pin.prefix(7)))")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if catalog.hasUpdate {
                Text("Update available").font(.caption).foregroundStyle(.orange)
                Button("Apply", action: onApply)
            } else {
                Text("Up to date").font(.caption).foregroundStyle(.secondary)
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct AddCatalogSheet: View {
    @Binding var url: String
    @Binding var ref: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Catalog").font(.headline)
            TextField("Git URL", text: $url,
                      prompt: Text("https://github.com/my-org/lanes-catalog.git"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
            TextField("Ref (branch, tag, or commit)", text: $ref,
                      prompt: Text("main — leave blank for the default branch"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { onAdd(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }
}

// MARK: - Items tab

/// The Items tab: one scrolling list with a section per scope (lane / repository).
/// Each row is a catalog item (checkbox to enable/disable) or a local script; the
/// enabled items and local scripts share one ordered, drag-reorderable group, and
/// not-yet-enabled catalog items follow.
struct ItemsTab: View {
    let root: URL
    @ObservedObject var model: CatalogsModel

    @State private var laneActive: [ConfigEdits.ActiveItem] = []
    @State private var laneAvailable: [ConfigEdits.Available] = []
    @State private var repoActive: [ConfigEdits.ActiveItem] = []
    @State private var repoAvailable: [ConfigEdits.Available] = []
    @State private var editing: ConfigEdits.ActiveItem?

    private var laneDir: URL { LaneFS.scriptDir(in: root) }
    private var repoDir: URL { LaneFS.repoScriptDir(in: root) }

    var body: some View {
        List {
            scopeSection("Lane actions", dir: laneDir, active: $laneActive, available: laneAvailable)
            scopeSection("Repository actions", dir: repoDir, active: $repoActive, available: repoAvailable)
        }
        .onAppear(perform: reload)
        .onChange(of: model.catalogs.count) { _, _ in reload() }
        .sheet(item: $editing) { item in
            PointerEditor(name: item.name, icon: item.icon) { name, icon in
                _ = try? ConfigEdits.renameActive(item, order: item.order, icon: icon, name: name)
                editing = nil
                reload()
            }
        }
    }

    @ViewBuilder
    private func scopeSection(_ title: String, dir: URL,
                              active: Binding<[ConfigEdits.ActiveItem]>,
                              available: [ConfigEdits.Available]) -> some View {
        let inactive = available.filter { a in
            !active.wrappedValue.contains { $0.pointer?.catalog == a.catalog && $0.pointer?.item == a.item }
        }
        Section(title) {
            if active.wrappedValue.isEmpty && inactive.isEmpty {
                Text("No catalog items or local scripts yet.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(active.wrappedValue) { item in
                activeRow(item, dir: dir)
                    .listRowBackground(Color.secondary.opacity(0.08))
            }
            .onMove { from, to in
                active.wrappedValue.move(fromOffsets: from, toOffset: to)
                ConfigEdits.applyOrder(active.wrappedValue)
                reload()
            }
            ForEach(inactive) { item in availableRow(item, dir: dir) }
        }
    }

    /// Shared row layout so active and inactive items look identical — same icon,
    /// name, description and source — differing only by the leading checkbox and
    /// a faint background on active rows.
    private func itemRow<L: View, T: View>(
        icon: String, name: String, detail: String?, source: String?,
        @ViewBuilder leading: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center, spacing: 8) {
            leading().frame(width: 18)
            Image(systemName: validSymbol(icon)).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                if let source, !source.isEmpty {
                    Text(source).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            trailing()
        }
    }

    private func activeRow(_ item: ConfigEdits.ActiveItem, dir: URL) -> some View {
        itemRow(icon: item.icon, name: item.name, detail: item.detail,
                source: item.isLocal ? "local" : item.pointer.map { model.name(for: $0.catalog) },
                leading: {
                    if item.isLocal {
                        Color.clear
                    } else {
                        Toggle("", isOn: Binding(get: { true }, set: { on in
                            if !on, let p = item.pointer {
                                ConfigEdits.removePointer(catalog: p.catalog, item: p.item, in: dir)
                                reload()
                            }
                        }))
                        .labelsHidden().toggleStyle(.checkbox)
                    }
                },
                trailing: {
                    if item.isLocal {
                        Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            .buttonStyle(.borderless).font(.caption)
                    } else {
                        Button { editing = item } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless)
                    }
                })
    }

    private func availableRow(_ item: ConfigEdits.Available, dir: URL) -> some View {
        itemRow(icon: item.icon, name: item.name, detail: item.detail,
                source: model.name(for: item.catalog),
                leading: {
                    Toggle("", isOn: Binding(get: { false }, set: { on in
                        if on {
                            try? ConfigEdits.addPointer(in: dir, catalog: item.catalog, item: item.item,
                                                        name: item.name, icon: item.icon)
                            reload()
                        }
                    }))
                    .labelsHidden().toggleStyle(.checkbox)
                },
                trailing: { EmptyView() })
    }

    private func reload() {
        laneActive = ConfigEdits.activeItems(in: laneDir, root: root)
        laneAvailable = ConfigEdits.available(root: root, subdir: "script")
        repoActive = ConfigEdits.activeItems(in: repoDir, root: root)
        repoAvailable = ConfigEdits.available(root: root, subdir: "script/repository")
    }
}

// MARK: - Hooks & template tab

/// The Hooks tab: a radio chooser per hook role (and the new-lane template), each
/// option showing its catalog source + description. Selection is held in state so
/// it reflects immediately, and written through to the `.catalog` pointer.
struct HooksTab: View {
    let root: URL
    @ObservedObject var model: CatalogsModel

    @State private var ticket: String?
    @State private var describe: String?
    @State private var template: String?

    var body: some View {
        Form {
            hookSection(LaneHooks.ticketHook, title: "Extract ticket", selection: $ticket,
                        blurb: "Runs on lane creation and ⌘R. Its output is treated as a ticket key and linked to the lane.")
            hookSection(LaneHooks.descriptionHook, title: "Update lane description", selection: $describe,
                        blurb: "Runs on lane creation and ⌘R. Its output becomes the lane's description (it may carry {{badge:…}} / {{refresh:…}}).")
            templateSection()
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadSelections)
        .onChange(of: model.catalogs.count) { _, _ in reloadSelections() }
    }

    @ViewBuilder
    private func hookSection(_ name: String, title: String,
                             selection: Binding<String?>, blurb: String) -> some View {
        let variants = ConfigEdits.available(root: root, subdir: "hook/\(name)")
        let hasLocal = ConfigEdits.hasLocalHook(name, root: root)
        Section {
            VStack(alignment: .leading, spacing: 10) {
                header(title, blurb)
                if variants.isEmpty && !hasLocal {
                    Text("No “\(name)” in your catalogs.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(variants) { item in
                    let k = key(item.catalog, item.item)
                    RadioRow(selected: selection.wrappedValue == k,
                             title: "\(item.name)  ·  \(model.name(for: item.catalog))",
                             detail: item.detail) {
                        selection.wrappedValue = k
                        try? ConfigEdits.setHookPointer(name, catalog: item.catalog, item: item.item, root: root)
                    }
                }
                RadioRow(selected: selection.wrappedValue == nil,
                         title: "Local",
                         detail: "Uses the local \(name) hook, if any.") {
                    selection.wrappedValue = nil
                    try? ConfigEdits.clearHookPointer(name, root: root)
                }
            }
        }
    }

    @ViewBuilder
    private func templateSection() -> some View {
        let variants = ConfigEdits.available(root: root, subdir: "template")
        Section {
            VStack(alignment: .leading, spacing: 10) {
                header("Template", "Copied into every new lane the first time it's created.")
                if variants.isEmpty {
                    Text("No templates in your catalogs.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(variants) { item in
                    let k = key(item.catalog, item.item)
                    RadioRow(selected: template == k,
                             title: "\(item.name)  ·  \(model.name(for: item.catalog))",
                             detail: item.detail) {
                        template = k
                        try? ConfigEdits.setTemplatePointer(catalog: item.catalog, item: item.item, root: root)
                    }
                }
                RadioRow(selected: template == nil,
                         title: "Local",
                         detail: "Uses the local template/ folder, if any.") {
                    template = nil
                    try? ConfigEdits.clearTemplatePointer(root: root)
                }
            }
        }
    }

    private func header(_ title: String, _ blurb: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(blurb).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func reloadSelections() {
        ticket = key(ConfigEdits.hookPointer(LaneHooks.ticketHook, root: root))
        describe = key(ConfigEdits.hookPointer(LaneHooks.descriptionHook, root: root))
        template = key(ConfigEdits.templatePointer(root: root))
    }

    private func key(_ pointer: Catalogs.Pointer?) -> String? {
        pointer.map { key($0.catalog, $0.item) }
    }

    private func key(_ catalog: String, _ item: String) -> String { "\(catalog)\u{1}\(item)" }
}

private struct RadioRow: View {
    let selected: Bool
    let title: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func validSymbol(_ name: String) -> String {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "scroll"
}

private struct PointerEditor: View {
    let onSave: (_ name: String, _ icon: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String

    init(name: String, icon: String, onSave: @escaping (String, String) -> Void) {
        self.onSave = onSave
        _name = State(initialValue: name)
        _icon = State(initialValue: icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit item").font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("SF Symbol", text: $icon, prompt: Text("scroll"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { onSave(name, icon) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
