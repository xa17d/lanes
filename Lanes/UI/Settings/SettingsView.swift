//
//  SettingsView.swift
//  Lanes
//
//  Root folder, ticket base URL, hotkey recorder, and the Automation deep-link.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var library: LaneLibrary
    @StateObject private var catalogs: CatalogsModel
    @AppStorage(SettingsKeys.ticketBaseURL) private var ticketBaseURL = ""

    init(library: LaneLibrary) {
        _library = ObservedObject(wrappedValue: library)
        _catalogs = StateObject(wrappedValue: CatalogsModel(library: library))
    }

    var body: some View {
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

            CatalogsSection(model: catalogs)

            if let root = library.root {
                ConfigEditorSection(root: root, model: catalogs)
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
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
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
