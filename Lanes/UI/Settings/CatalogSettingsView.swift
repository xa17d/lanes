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

/// The Items tab: two scope sections (lane actions + repository actions), each a
/// two-pane Available/Active editor over `.catalog` pointers and local scripts.
struct ItemsTab: View {
    let root: URL
    @ObservedObject var model: CatalogsModel

    var body: some View {
        Form {
            ItemScopeEditor(title: "Lane actions", subdir: "script",
                            dir: LaneFS.scriptDir(in: root), root: root, model: model)
            ItemScopeEditor(title: "Repository actions", subdir: "script/repository",
                            dir: LaneFS.repoScriptDir(in: root), root: root, model: model)
        }
        .formStyle(.grouped)
    }
}

private struct ItemScopeEditor: View {
    let title: String
    let subdir: String
    let dir: URL
    let root: URL
    @ObservedObject var model: CatalogsModel

    @State private var available: [ConfigEdits.Available] = []
    @State private var active: [ConfigEdits.Entry] = []
    @State private var locals: [ConfigEdits.LocalItem] = []
    @State private var editing: ConfigEdits.Entry?

    private var activeKeys: Set<String> {
        Set(active.map { key($0.pointer.catalog, $0.pointer.item) })
    }

    var body: some View {
        Section(title) {
            HStack(alignment: .top, spacing: 14) {
                pane("Available") { availableList }
                pane("Active — drag to reorder") { activeList }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: model.catalogs.count) { _, _ in reload() }
        .sheet(item: $editing) { entry in
            PointerEditor(entry: entry) { name, icon in
                _ = try? ConfigEdits.updatePointer(entry, order: entry.order, icon: icon, name: name)
                editing = nil
                reload()
            }
        }
    }

    private func pane<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content().frame(height: 220).frame(maxWidth: .infinity)
        }
    }

    private var availableList: some View {
        List {
            if available.isEmpty {
                Text("No catalog items").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(available) { item in
                Toggle(isOn: toggleBinding(for: item)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        if let detail = item.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.name(for: item.catalog)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .listStyle(.bordered)
    }

    private var activeList: some View {
        List {
            ForEach(active) { entry in
                HStack {
                    Image(systemName: validSymbol(entry.icon)).frame(width: 16).foregroundStyle(.secondary)
                    Text(entry.name)
                    Text(model.name(for: entry.pointer.catalog)).font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button { editing = entry } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                }
            }
            .onMove(perform: reorder)
            ForEach(locals) { local in
                HStack {
                    Image(systemName: validSymbol(local.icon)).frame(width: 16).foregroundStyle(.secondary)
                    Text(local.name)
                    Text("local").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([local.url]) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .listStyle(.bordered)
    }

    private func toggleBinding(for item: ConfigEdits.Available) -> Binding<Bool> {
        Binding(
            get: { activeKeys.contains(key(item.catalog, item.item)) },
            set: { on in
                if on {
                    try? ConfigEdits.addPointer(in: dir, catalog: item.catalog, item: item.item,
                                                name: item.name, icon: item.icon)
                } else {
                    ConfigEdits.removePointer(catalog: item.catalog, item: item.item, in: dir)
                }
                reload()
            }
        )
    }

    private func reorder(from: IndexSet, to: Int) {
        var list = active
        list.move(fromOffsets: from, toOffset: to)
        try? ConfigEdits.applyOrder(list)
        reload()
    }

    private func reload() {
        available = ConfigEdits.available(root: root, subdir: subdir)
        active = ConfigEdits.pointers(in: dir)
        locals = ConfigEdits.localItems(in: dir)
    }

    private func key(_ catalog: String, _ item: String) -> String { "\(catalog)\u{1}\(item)" }
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
                         title: hasLocal ? "Local file" : "None",
                         detail: hasLocal ? "Use the local hook script in .lanes/config/hook." : nil) {
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
                         title: "None — use the local template/ folder, if any", detail: nil) {
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
    let entry: ConfigEdits.Entry
    let onSave: (_ name: String, _ icon: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String

    init(entry: ConfigEdits.Entry, onSave: @escaping (String, String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _name = State(initialValue: entry.name)
        _icon = State(initialValue: entry.icon)
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
