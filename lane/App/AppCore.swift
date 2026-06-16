//
//  AppCore.swift
//  lane
//
//  Single source of truth shared by the AppDelegate (status item, hotkey,
//  panel) and the SwiftUI Settings scene.
//

import Foundation

@MainActor
final class AppCore {
    static let shared = AppCore()

    let library = TrackLibrary()
    lazy var model = LaneModel(library: library, services: Self.makeServices(), registry: .default)
    lazy var panel = PanelController(model: model)

    private init() {}

    private static func makeServices() -> Services {
        Services(jiraBaseURL: {
            UserDefaults.standard.string(forKey: SettingsKeys.jiraBaseURL).flatMap { URL(string: $0) }
        })
    }
}

nonisolated enum SettingsKeys {
    static let jiraBaseURL = "jiraBaseURL"
}
