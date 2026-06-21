//
//  AppCore.swift
//  Lanes
//
//  Single source of truth shared by the AppDelegate (status item, hotkey,
//  panel) and the SwiftUI Settings scene.
//

import Foundation

@MainActor
final class AppCore {
    static let shared = AppCore()

    let library = LaneLibrary()
    lazy var model = LaneModel(library: library, services: Self.makeServices(), registry: .default)
    lazy var panel = PanelController(model: model)
    lazy var settings = SettingsWindowController(library: library)

    private init() {}

    private static func makeServices() -> Services {
        Services(ticketBaseURL: {
            UserDefaults.standard.string(forKey: SettingsKeys.ticketBaseURL).flatMap { URL(string: $0) }
        })
    }
}

nonisolated enum SettingsKeys {
    /// Legacy "jiraBaseURL" string is kept so an already-configured base URL
    /// survives the rename to generic "ticket" vocabulary.
    static let ticketBaseURL = "jiraBaseURL"
}
