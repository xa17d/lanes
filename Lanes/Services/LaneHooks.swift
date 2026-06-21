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
//  A description may also declare `{{refresh:<duration>}}`; when it does, the
//  UI re-runs update-lane-description (via `refreshIfStale`) once that interval
//  has elapsed and the lane/list is shown again.
//

import Foundation

nonisolated struct LaneHooks: Sendable {
    let shell: Shell
    let baseURL: @Sendable () -> URL?

    static let ticketHook = "extract-ticket"
    static let descriptionHook = "update-lane-description"

    /// Per-lane store key tracking the last `update-lane-description` run, used
    /// by the `{{refresh:…}}` directive to decide when a description is stale.
    static let refreshKey = "description-refresh"
    nonisolated struct RefreshState: Codable, Sendable { var lastRunAt: Date }

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
        return applyDescription(to: lane, root: root, store: store) ?? lane
    }

    /// Re-run `update-lane-description` only if the lane's description declares a
    /// `{{refresh:…}}` interval that has elapsed since the last run. Returns the
    /// updated lane, or nil when nothing changed (no directive, not yet stale,
    /// hook absent, or empty output). Meant to be called off the main actor.
    func refreshIfStale(_ lane: Lane, root: URL, now: Date = Date()) -> Lane? {
        guard let interval = DescriptionMarkup.parse(from: lane.summary).refresh,
              hookExists(Self.descriptionHook, root: root) else { return nil }
        let store = LaneStore(lane: lane)
        if let last = store.value(RefreshState.self, Self.refreshKey)?.lastRunAt,
           now.timeIntervalSince(last) < interval { return nil }
        return applyDescription(to: lane, root: root, store: store)
    }

    // MARK: - Individual hooks

    /// Run `update-lane-description`, record the run time (so the `{{refresh:…}}`
    /// clock advances even on empty/failed output, preventing re-run storms), and
    /// return the lane with the new description — or nil when the hook is absent
    /// or produced nothing.
    private func applyDescription(to lane: Lane, root: URL, store: LaneStore) -> Lane? {
        guard hookExists(Self.descriptionHook, root: root) else { return nil }
        let desc = runDescription(for: lane, root: root, store: store)
        try? store.setValue(RefreshState(lastRunAt: Date()), Self.refreshKey)
        guard let desc else { return nil }
        return (try? LaneFS.setSummary(lane, to: desc)) ?? lane
    }

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

    /// The effective executable for hook `name`: a `<name>.catalog` pointer wins
    /// over a local `<name>` file (delete the pointer to fall back to local), and
    /// the resolved target must itself be an executable regular file. nil when
    /// neither is present/runnable.
    private func hookURL(_ name: String, root: URL) -> URL? {
        let dir = LaneFS.hookDir(in: root)
        let fm = FileManager.default
        let pointer = dir.appendingPathComponent("\(name).\(Catalogs.pointerExtension)")
        if fm.fileExists(atPath: pointer.path),
           let target = Catalogs.resolvePointer(at: pointer, root: root),
           fm.isExecutableFile(atPath: target.path) {
            return target
        }
        let local = dir.appendingPathComponent(name)
        let isRegular = (try? local.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        return (isRegular && fm.isExecutableFile(atPath: local.path)) ? local : nil
    }

    /// Whether hook `name` resolves to a runnable executable.
    private func hookExists(_ name: String, root: URL) -> Bool {
        hookURL(name, root: root) != nil
    }

    /// Run hook `name` (cwd = the lane dir) and return its trimmed stdout, or
    /// nil when the hook is absent/not executable, fails, or prints nothing.
    private func stdout(of name: String, for lane: Lane, root: URL, env: [String: String]) -> String? {
        guard let url = hookURL(name, root: root) else { return nil }
        guard let out = try? shell.run(url.path, [], cwd: lane.url, env: env) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
