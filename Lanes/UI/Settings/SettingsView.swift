//
//  SettingsView.swift
//  Lanes
//
//  Root folder, ticket base URL, hotkey recorder, and the Automation deep-link.
//

import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts

/// The Settings sidebar panes.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general = "General", catalogs = "Catalogs", items = "Items", hooks = "Hooks"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .catalogs: return "shippingbox"
        case .items: return "list.bullet"
        case .hooks: return "bolt.badge.clock"
        }
    }
}

/// Shared selection so an opener (e.g. the lane-list update banner) can jump the
/// reused Settings window to a specific pane.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane? = .general
}

struct SettingsView: View {
    @ObservedObject var library: LaneLibrary
    @ObservedObject var nav: SettingsNavigation
    @StateObject private var catalogs: CatalogsModel
    @AppStorage(SettingsKeys.ticketBaseURL) private var ticketBaseURL = ""

    init(library: LaneLibrary, nav: SettingsNavigation) {
        _library = ObservedObject(wrappedValue: library)
        _nav = ObservedObject(wrappedValue: nav)
        _catalogs = StateObject(wrappedValue: CatalogsModel(library: library))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $nav.pane) { pane in
                Label(pane.rawValue, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 210)
        } detail: {
            detail(nav.pane ?? .general)
                .navigationTitle((nav.pane ?? .general).rawValue)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 480, idealHeight: 660)
    }

    @ViewBuilder
    private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            generalTab
        case .catalogs:
            Form { CatalogsSection(model: catalogs) }.formStyle(.grouped)
        case .items:
            itemsTab
        case .hooks:
            hooksTab
        }
    }

    private var generalTab: some View {
        Form {
            Section("Root folder") {
                HStack {
                    Text(library.root?.path ?? "Not set")
                        .font(.system(size: 12, design: library.root == nil ? .default : .monospaced))
                        .foregroundStyle(library.root == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseRoot() }
                }
                Text("Every visible folder inside the root is a lane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tickets") {
                TextField("Base URL", text: $ticketBaseURL,
                          prompt: Text("https://yourco.atlassian.net/browse/"))
                    .textFieldStyle(.roundedBorder)
                Text("Used to build ticket URLs from keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Lanes", name: .toggleLane)
            }

            Section("Permissions") {
                Button("Open Automation settings…") {
                    Permissions.openAutomationSettings()
                }
                Text("Lanes controls Chrome and iTerm via Apple Events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var itemsTab: some View {
        if let root = library.root {
            ItemsTab(root: root, model: catalogs)
        } else {
            noRootNotice
        }
    }

    @ViewBuilder
    private var hooksTab: some View {
        if let root = library.root {
            HooksTab(root: root, model: catalogs)
        } else {
            noRootNotice
        }
    }

    private var noRootNotice: some View {
        Text("Choose a root folder on the General pane first.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your lanes."
        if let current = library.root { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url {
            library.setRoot(url)
        }
    }
}
