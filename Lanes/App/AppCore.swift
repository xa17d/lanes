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
    static let ticketBaseURL = "ticketBaseURL"
    /// Set once the user acknowledges the one-time warning that catalogs run
    /// shared code on their machine (shown before the first catalog is added).
    static let catalogTrustAcknowledged = "catalogTrustAcknowledged"
}
