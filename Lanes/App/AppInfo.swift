//
//  AppInfo.swift
//  Lanes
//
//  App version, read from the bundle's Info.plist. The values come from
//  MARKETING_VERSION / CURRENT_PROJECT_VERSION in the Xcode project — bump
//  MARKETING_VERSION when shipping a change (see CLAUDE.md).
//

import Foundation

nonisolated enum AppInfo {
    /// Marketing version string, e.g. `1.0`.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number, e.g. `1`.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// Version with build for display, e.g. `1.0 (1)`.
    static var versionString: String { "\(version) (\(build))" }
}
