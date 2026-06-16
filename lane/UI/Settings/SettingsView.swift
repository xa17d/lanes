//
//  SettingsView.swift
//  lane
//
//  Root folder, Jira base URL, hotkey recorder, and the Automation deep-link.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var library: TrackLibrary
    @AppStorage(SettingsKeys.jiraBaseURL) private var jiraBaseURL = ""

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
                Text("Every visible folder inside the root is a track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Jira") {
                TextField("Base URL", text: $jiraBaseURL,
                          prompt: Text("https://yourco.atlassian.net/browse/"))
                    .textFieldStyle(.roundedBorder)
                Text("Used to build ticket URLs from keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Toggle Lane", name: .toggleLane)
            }

            Section("Permissions") {
                Button("Open Automation settings…") {
                    Permissions.openAutomationSettings()
                }
                Text("Lane controls Chrome and iTerm via Apple Events.")
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
        panel.message = "Choose the folder that holds your tracks."
        if let current = library.root { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url {
            library.setRoot(url)
        }
    }
}
