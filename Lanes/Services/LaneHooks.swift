//
//  LaneHooks.swift
//  Lanes
//
//  Lifecycle hook scripts under the root's `.lanes/config/hooks/`, run when a
//  lane is created and on demand (⌘R). They fire in a fixed order so a later
//  hook can build on an earlier one:
//
//    1. extract-ticket          — its stdout (a ticket key) is linked to the lane.
//    2. update-lane-description  — its stdout becomes the lane description; it
//                                  runs with TICKET_KEY/TICKET_URL of the lane's
//                                  primary ticket already exported, so the
//                                  description can reference the extracted ticket.
//

import Foundation

nonisolated struct LaneHooks: Sendable {
    let shell: Shell
    let baseURL: @Sendable () -> URL?

    static let ticketHook = "extract-ticket"
    static let descriptionHook = "update-lane-description"

    init(shell: Shell, baseURL: @escaping @Sendable () -> URL? = { nil }) {
        self.shell = shell
        self.baseURL = baseURL
    }

    /// Run every lifecycle hook for `lane`, in their defined order, persisting
    /// each effect (ticket links into the lane store, description into
    /// `lane.json`). Returns the lane with any description update applied;
    /// ticket links persist to the store but don't change the Lane value.
    /// Missing/failed hooks and filesystem errors are no-ops, so callers keep
    /// the existing lane.
    @discardableResult
    func apply(to lane: Lane, root: URL) -> Lane {
        let store = LaneStore(lane: lane)
        extractTicket(for: lane, root: root, store: store)
        if let desc = runDescription(for: lane, root: root, store: store) {
            return (try? LaneFS.setSummary(lane, to: desc)) ?? lane
        }
        return lane
    }

    // MARK: - Individual hooks

    /// `extract-ticket`: treat its trimmed stdout as a ticket key and link it to
    /// the lane (idempotent — re-running never duplicates the ticket).
    private func extractTicket(for lane: Lane, root: URL, store: LaneStore) {
        guard let key = stdout(of: Self.ticketHook, for: lane, root: root, env: laneEnv(lane))
        else { return }
        _ = try? TicketProvider.link(key: key, store: store)
    }

    /// `update-lane-description`: its trimmed stdout becomes the description,
    /// with the lane's primary ticket exported as TICKET_KEY/TICKET_URL.
    private func runDescription(for lane: Lane, root: URL, store: LaneStore) -> String? {
        var env = laneEnv(lane)
        if let ticket = TicketProvider.primaryEnv(store: store, baseURL: baseURL) {
            env["TICKET_KEY"] = ticket.key
            env["TICKET_URL"] = ticket.url
        }
        return stdout(of: Self.descriptionHook, for: lane, root: root, env: env)
    }

    // MARK: - Internals

    private func laneEnv(_ lane: Lane) -> [String: String] {
        ["LANE_DIR": lane.url.path, "LANE_NAME": lane.name, "LANE_ID": lane.id.uuidString]
    }

    /// Run hook `name` (cwd = the lane dir) and return its trimmed stdout, or
    /// nil when the hook is absent/not executable, fails, or prints nothing.
    private func stdout(of name: String, for lane: Lane, root: URL, env: [String: String]) -> String? {
        let url = LaneFS.hooksDir(in: root).appendingPathComponent(name)
        let fm = FileManager.default
        let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegular, fm.isExecutableFile(atPath: url.path) else { return nil }
        guard let out = try? shell.run(url.path, [], cwd: lane.url, env: env) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
