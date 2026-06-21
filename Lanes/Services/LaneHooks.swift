//
//  LaneHooks.swift
//  Lanes
//
//  Lifecycle hook scripts under the root's `.lanes/config/hooks/`. Currently
//  just `update-lane-description`: run when a lane is created and on demand
//  (⌘R), its stdout becomes the lane's description.
//

import Foundation

nonisolated struct LaneHooks: Sendable {
    let shell: Shell

    static let descriptionHook = "update-lane-description"

    /// Run `update-lane-description` for `lane` (cwd = the lane dir, with
    /// LANE_DIR/LANE_NAME/LANE_ID exported) and return its trimmed stdout.
    /// Returns nil when the hook is absent/not executable, fails, or prints
    /// nothing — callers should leave the existing description untouched.
    func description(for lane: Lane, root: URL) -> String? {
        let url = LaneFS.hooksDir(in: root).appendingPathComponent(Self.descriptionHook)
        let fm = FileManager.default
        let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegular, fm.isExecutableFile(atPath: url.path) else { return nil }

        let env = ["LANE_DIR": lane.url.path, "LANE_NAME": lane.name, "LANE_ID": lane.id.uuidString]
        guard let out = try? shell.run(url.path, [], cwd: lane.url, env: env) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
