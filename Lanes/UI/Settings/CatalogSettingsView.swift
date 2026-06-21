//
//  CatalogSettingsView.swift
//  Lanes
//
//  Settings UI for catalogs: subscribe/sync/apply/remove shared config repos,
//  and a file-backed editor that enables/orders catalog items and binds the
//  hooks / new-lane template to catalog content (all via `.catalog` pointers).
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

// MARK: - Config editor

struct ConfigEditorSection: View {
    let root: URL
    @ObservedObject var model: CatalogsModel

    @State private var laneScripts: [ConfigEdits.Entry] = []
    @State private var repoScripts: [ConfigEdits.Entry] = []
    @State private var editing: ConfigEdits.Entry?

    var body: some View {
        Section("Catalog items") {
            if model.catalogs.isEmpty {
                Text("Add a catalog to enable shared scripts, hooks, and templates here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                scriptList("Lane scripts", entries: $laneScripts,
                           dir: LaneFS.scriptDir(in: root), subdir: "script")
                scriptList("Repository scripts", entries: $repoScripts,
                           dir: LaneFS.repoScriptDir(in: root), subdir: "script/repository")
                hookRow(LaneHooks.ticketHook)
                hookRow(LaneHooks.descriptionHook)
                templateRow()
            }
        }
        .onAppear(perform: reload)
        .onChange(of: model.catalogs.count) { _, _ in reload() }
        .popover(item: $editing) { entry in
            PointerEditor(entry: entry) { name, icon in
                _ = try? ConfigEdits.updatePointer(entry, order: entry.order, icon: icon, name: name)
                editing = nil
                reload()
            }
        }
    }

    // MARK: Scripts

    @ViewBuilder
    private func scriptList(_ title: String, entries: Binding<[ConfigEdits.Entry]>,
                            dir: URL, subdir: String) -> some View {
        let items = entries.wrappedValue
        LabeledContent(title) {
            Menu("Add from catalog") {
                let available = ConfigEdits.available(root: root, subdir: subdir)
                if available.isEmpty {
                    Text("No items in your catalogs")
                } else {
                    ForEach(available) { item in
                        Button("\(item.name)  ·  \(model.name(for: item.catalog))") {
                            try? ConfigEdits.addPointer(in: dir, catalog: item.catalog,
                                                        item: item.item, name: item.name, icon: item.icon)
                            reload()
                        }
                        .help(item.detail ?? "")
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
            HStack {
                Image(systemName: validSymbol(entry.icon))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(entry.name)
                Text(model.name(for: entry.pointer.catalog)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { move(entries, index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                Button { move(entries, index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).disabled(index == items.count - 1)
                Button { editing = entry } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                Button(role: .destructive) {
                    try? ConfigEdits.remove(entry.url); reload()
                } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func move(_ entries: Binding<[ConfigEdits.Entry]>, _ index: Int, by delta: Int) {
        var list = entries.wrappedValue
        let target = index + delta
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        try? ConfigEdits.applyOrder(list)
        reload()
    }

    // MARK: Hooks & template

    @ViewBuilder
    private func hookRow(_ name: String) -> some View {
        LabeledContent(name) {
            HStack {
                if let pointer = ConfigEdits.hookPointer(name, root: root) {
                    Text("→ \(model.name(for: pointer.catalog))").font(.caption).foregroundStyle(.secondary)
                    Button("Clear") { try? ConfigEdits.clearHookPointer(name, root: root); reload() }
                } else {
                    Menu("Set from catalog") {
                        let available = ConfigEdits.available(root: root, subdir: "hook/\(name)")
                        if available.isEmpty {
                            Text("No “\(name)” in your catalogs")
                        } else {
                            ForEach(available) { item in
                                Button("\(item.name)  ·  \(model.name(for: item.catalog))") {
                                    try? ConfigEdits.setHookPointer(name, catalog: item.catalog,
                                                                    item: item.item, root: root)
                                    reload()
                                }
                                .help(item.detail ?? "")
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
    }

    @ViewBuilder
    private func templateRow() -> some View {
        LabeledContent("template") {
            HStack {
                if let pointer = ConfigEdits.templatePointer(root: root) {
                    Text("→ \(model.name(for: pointer.catalog))").font(.caption).foregroundStyle(.secondary)
                    Button("Clear") { try? ConfigEdits.clearTemplatePointer(root: root); reload() }
                } else {
                    Menu("Set from catalog") {
                        let available = ConfigEdits.available(root: root, subdir: "template")
                        if available.isEmpty {
                            Text("No template in your catalogs")
                        } else {
                            ForEach(available) { item in
                                Button("\(item.name)  ·  \(model.name(for: item.catalog))") {
                                    try? ConfigEdits.setTemplatePointer(catalog: item.catalog,
                                                                        item: item.item, root: root)
                                    reload()
                                }
                                .help(item.detail ?? "")
                            }
                        }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
    }

    private func reload() {
        laneScripts = ConfigEdits.pointers(in: LaneFS.scriptDir(in: root))
        repoScripts = ConfigEdits.pointers(in: LaneFS.repoScriptDir(in: root))
    }

    private func validSymbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "scroll"
    }
}

private struct PointerEditor: View {
    let entry: ConfigEdits.Entry
    let onSave: (_ name: String, _ icon: String) -> Void
    @State private var name: String
    @State private var icon: String

    init(entry: ConfigEdits.Entry, onSave: @escaping (String, String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _name = State(initialValue: entry.name)
        _icon = State(initialValue: entry.icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit item").font(.headline)
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 240)
            TextField("SF Symbol", text: $icon, prompt: Text("scroll"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Save") { onSave(name, icon) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
