//
//  LaneModel.swift
//  Lanes
//
//  The navigation + search view model. Owns the level stack, selection, and
//  query, and drives streaming loads. Level 0 (the lane list) is implicit:
//  when `stack` is empty we show lanes; otherwise we show `stack.last`.
//

import Foundation
import Combine

@MainActor
final class LaneModel: ObservableObject {
    let library: LaneLibrary
    let services: Services
    let registry: ProviderRegistry
    let keepAwake: KeepAwake
    private var cancellables = Set<AnyCancellable>()
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    /// Open Settings focused on the Catalogs pane (from the lane-list update banner).
    var onOpenCatalogSettings: () -> Void = {}

    @Published var lanes: [Lane] = []
    /// True when a subscribed catalog has a fetched update not yet applied —
    /// surfaced as a banner in the lane list.
    @Published var catalogUpdatesAvailable = false
    @Published var stack: [LevelState] = []
    @Published var query: String = "" { didSet { selection = 0 } }
    @Published var inputText: String = ""
    @Published var selection: Int = 0
    @Published var toast: ToastState?
    @Published var includeArchived = false
    @Published var panelAppeared = false
    /// True while an explicit ⌘R refresh (hooks + reload) is running, so the UI
    /// can show a spinner. Not set by the passive {{refresh:…}} auto-refresh.
    @Published var isRefreshing = false
    /// True while a selected item's action is executing (e.g. a script), so the
    /// panel shows a spinner instead of looking frozen.
    @Published private(set) var isRunningAction = false

    /// Background clones in progress. Each shows a spinner row in its lane until
    /// it finishes; multiple can run at once (clones never block the panel).
    @Published private(set) var activeClones: [CloneJob] = []

    /// Lanes whose `{{refresh:…}}` hook is currently re-running, so frequent
    /// re-renders don't spawn duplicate runs for the same lane.
    private var refreshingLaneIDs: Set<Lane.ID> = []

    init(library: LaneLibrary, services: Services, registry: ProviderRegistry, keepAwake: KeepAwake) {
        self.library = library
        self.services = services
        self.registry = registry
        self.keepAwake = keepAwake
        // Re-render when keep-awake toggles so the launcher row reflects it.
        keepAwake.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Hard reset to the root lane list. Used on first launch and as the
    /// fallback when the level we were on is no longer valid.
    func reset() {
        stack = []
        query = ""
        selection = 0
        reloadLanes()
    }

    /// Called when the panel is re-shown via the hotkey. Returns you to where
    /// you left off (the navigation stack is kept in memory, so this only holds
    /// within a single process — a restart starts with an empty stack = root).
    /// Refreshes the root list for external changes, and falls back to the root
    /// if the lane we were inside has since vanished on disk.
    func reopen() {
        if let lane = currentLane,
           !FileManager.default.fileExists(atPath: lane.url.path) {
            reset()
            return
        }
        if stack.isEmpty {
            reloadLanes()      // pick up external add / rename / delete
        } else if let lane = currentLane {
            kickStaleRefresh(lane)   // refresh the open lane's description if due
        }
        if !rows.indices.contains(selection) { selection = 0 }
    }

    func reloadLanes() {
        lanes = library.lanes(includeArchived: includeArchived)
        for lane in lanes { kickStaleRefresh(lane) }
        refreshCatalogIndicator()
    }

    /// Recompute whether any subscribed catalog has an update waiting (a cheap
    /// disk check, done off-main). Drives the lane-list update banner.
    func refreshCatalogIndicator() {
        guard let root = library.root else { catalogUpdatesAvailable = false; return }
        Task.detached {
            let available = Catalogs.anyUpdatesAvailable(root: root)
            await MainActor.run { self.catalogUpdatesAvailable = available }
        }
    }

    /// Lazily re-run a lane's `update-lane-description` hook when its description
    /// declares a `{{refresh:…}}` interval that has elapsed. Cheap on the main
    /// actor (a parse + set check); the hook runs off-main and the result folds
    /// back into the list/header. The in-flight set guards against duplicate runs
    /// while a slow hook is in progress.
    private func kickStaleRefresh(_ lane: Lane) {
        guard let root = library.root,
              DescriptionMarkup.parse(from: lane.summary).refresh != nil,
              !refreshingLaneIDs.contains(lane.id) else { return }
        refreshingLaneIDs.insert(lane.id)
        let hooks = services.hooks
        Task.detached {
            let updated = hooks.refreshIfStale(lane, root: root)
            await MainActor.run {
                self.refreshingLaneIDs.remove(lane.id)
                if let updated { self.applyLaneUpdate(updated) }
            }
        }
    }

    /// Toggle archived lanes in the level-0 list (so they can be unarchived).
    func toggleArchived() {
        guard stack.isEmpty else { return }
        includeArchived.toggle()
        selection = 0
        reloadLanes()
    }

    var currentLevel: LevelState? { stack.last }
    var currentLane: Lane? { stack.first?.lane }

    var breadcrumb: [String] { stack.compactMap(\.titleSegment) }

    var isInputMode: Bool {
        if case .input = currentLevel?.kind { return true }
        return false
    }

    var currentInputRequest: InputRequest? {
        if case .input(let request)? = currentLevel?.kind { return request }
        return nil
    }

    // MARK: - Rows

    var rows: [DisplayRow] {
        if isInputMode { return [] }
        if stack.isEmpty { return laneRows() }
        let base = itemRows(for: stack[stack.count - 1])
        // Overlay in-progress clone spinners at the lane's top level.
        if stack.count == 1, query.isEmpty, let lane = currentLane {
            return cloneRows(for: lane, existing: base) + base
        }
        return base
    }

    private func laneRows() -> [DisplayRow] {
        // Parse each lane's description markup once, then reuse it for both
        // scoring (body + badge text) and the row's display/badge.
        let parsed = lanes.map { (lane: $0, markup: DescriptionMarkup.parse(from: $0.summary)) }
        let matched: [(lane: Lane, markup: DescriptionMarkup)]
        if query.isEmpty {
            matched = parsed
        } else {
            matched = parsed
                .compactMap { entry -> (lane: Lane, markup: DescriptionMarkup, score: Double)? in
                    // Match against the folder name and the description body +
                    // status text; keep the best score.
                    let nameScore = FuzzyMatcher.score(query: query, title: entry.lane.name)
                    let descScore = FuzzyMatcher.score(query, entry.markup.searchText)
                    guard let best = [nameScore, descScore].compactMap({ $0 }).max() else { return nil }
                    return (entry.lane, entry.markup, best)
                }
                .sorted { $0.score > $1.score }
                .map { (lane: $0.lane, markup: $0.markup) }
        }
        var rows = matched.map { entry -> DisplayRow in
            // Description big, folder name smaller below; the status badge (if
            // any) is parsed out of the description.
            let t = entry.lane
            let markup = entry.markup
            let hasBody = !markup.body.isEmpty
            let title = hasBody ? markup.body : t.name
            let subtitle: String?
            if hasBody {
                subtitle = t.isArchived ? "\(t.name) · archived" : t.name
            } else {
                subtitle = t.isArchived ? "archived" : nil
            }
            return DisplayRow(id: "lane:\(t.id)", title: title, subtitle: subtitle,
                              icon: .folder, pathLabels: [], badge: markup.badge,
                              payload: .lane(t))
        }
        // "New lane…" is always last.
        if let root = library.root {
            let item = LaneActions.newLaneItem(root: root, hooks: services.hooks)
            rows.append(DisplayRow(item: item, pathLabels: []))
        }
        return rows
    }

    // MARK: - Keep awake

    var keepAwakeActive: Bool { keepAwake.isActive }

    /// Toggle the system keep-awake (bound to ⌘K while the panel is open and the
    /// banner's "Turn Off" button).
    func toggleKeepAwake() { keepAwake.toggle() }

    private func itemRows(for level: LevelState) -> [DisplayRow] {
        if query.isEmpty {
            return level.items.map { DisplayRow(item: $0, pathLabels: []) }
        }
        let hits = SubtreeIndex.search(level.index, query: query)
        // If nothing matched, let the container turn the query into an action
        // (e.g. "Clone repo…" clones a pasted URL). A short/typo query yields no
        // fallback, so this only fires for a recognizable URL.
        if hits.isEmpty, let fallback = level.queryFallback, let item = fallback(query) {
            return [DisplayRow(item: item, pathLabels: [])]
        }
        return hits.map { DisplayRow(item: $0.item, pathLabels: $0.breadcrumb) }
    }

    var selectedRow: DisplayRow? {
        let r = rows
        guard r.indices.contains(selection) else { return nil }
        return r[selection]
    }

    // MARK: - Key actions

    func moveSelection(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    /// Return / Enter. Submits in input mode, else activates the selection.
    /// `stayInMenu` (⇧Return) keeps the current level open after a `.startClone`
    /// so several repos can be queued from the clone menu without navigating
    /// back into the lane; it's inert for every other action.
    func confirm(stayInMenu: Bool = false) {
        if isInputMode { submitInput(); return }
        activateSelected(stayInMenu: stayInMenu)
    }

    func activateSelected(stayInMenu: Bool = false) {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .lane(let t): enter(lane: t)
        case .item(let item): activate(item: item, stayInMenu: stayInMenu)
        }
    }

    /// Right arrow: enter a lane or a container — identical to activating the
    /// selection. (Management lives inside the lane as the "Manage lane…" item,
    /// so → on a lane behaves like Enter rather than opening a separate menu.)
    func drillRight() { activateSelected() }

    /// ⌃U: clear the active text field (the search query, or the input field in
    /// input mode) — like clearing the line in a terminal.
    func clearField() {
        if isInputMode { inputText = "" } else { query = "" }
    }

    func escape() {
        if isInputMode {
            pop()                       // cancel input
        } else if !query.isEmpty {
            query = ""
        } else if stack.isEmpty {
            onClose()
        } else {
            pop()
        }
    }

    func newLane() {
        guard let root = library.root else {
            showToast("Set a root folder in Settings (⌘,) first.", kind: .error)
            return
        }
        // Carry whatever was typed in the search field into the name field as
        // a starting suggestion.
        pushInput(LaneActions.newLaneRequest(root: root, hooks: services.hooks), seed: query)
    }

    func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        query = ""
        selection = 0
        if stack.isEmpty { reloadLanes() }
    }

    func reloadCurrent() {
        if stack.isEmpty {
            reloadLanes()
        } else if let level = stack.last {
            if let source = level.sourceItem {
                loadLevel(level.id, from: .children(source), keepVisible: false)
            } else if let lane = currentLane {
                loadLevel(level.id, from: .lane(lane), keepVisible: false)
            }
        }
    }

    /// Reload the current level's items *without* blanking the visible list, so
    /// the list never flashes empty (⌘R on the open lane, post-clone reload).
    private func reloadCurrentInPlace() {
        guard let level = stack.last else { return }
        if let source = level.sourceItem {
            loadLevel(level.id, from: .children(source), keepVisible: true)
        } else if let lane = currentLane {
            loadLevel(level.id, from: .lane(lane), keepVisible: true)
        }
    }

    /// ⌘R: re-run the lifecycle hooks (extract-ticket → update-lane-description)
    /// off the main thread, then fold their effects back in and reload the
    /// current level. Shows a spinner for the duration and reloads the list in
    /// place (no empty flash). Re-entrancy is ignored while one is in flight.
    func refresh() {
        guard !isRefreshing else { return }
        guard let root = library.root else { reloadCurrent(); return }
        isRefreshing = true
        let hooks = services.hooks
        if stack.isEmpty {
            let targets = lanes
            Task.detached {
                for lane in targets { _ = hooks.apply(to: lane, root: root) }
                await MainActor.run {
                    self.isRefreshing = false
                    self.reloadLanes()      // diffs in place — no flicker
                }
            }
        } else if let lane = currentLane {
            Task.detached {
                let updated = hooks.apply(to: lane, root: root)
                await MainActor.run {
                    self.isRefreshing = false
                    self.applyLaneUpdate(updated)
                    self.reloadCurrentInPlace()
                }
            }
        } else {
            isRefreshing = false
        }
    }

    /// Reflect a refreshed lane's metadata in the in-memory caches (the list
    /// row and, if it's the open lane, the header).
    private func applyLaneUpdate(_ lane: Lane) {
        if let i = lanes.firstIndex(where: { $0.id == lane.id }) { lanes[i] = lane }
        if !stack.isEmpty, stack[0].lane?.id == lane.id { stack[0].lane = lane }
    }

    // MARK: - Background clone

    /// Start a non-blocking clone of `url` into `lane`. Registers a spinner job
    /// (shown as a row in the lane until done), runs the clone off-main, and on
    /// completion drops the job, surfaces any warning/error, and reloads the lane
    /// in place if it's the one on screen — so several clones can run at once
    /// without ever blocking the panel.
    /// Starts a background clone, returning the repo name when a job was
    /// actually enqueued or nil when it was skipped (bad URL, already present,
    /// or the same clone is already running) so callers can confirm accordingly.
    @discardableResult
    func startClone(url: String, into lane: Lane) -> String? {
        guard let repo = RepoRegistry.makeRepo(url: url, now: Date()) else {
            showToast("Not a recognizable clone URL.", kind: .error); return nil
        }
        // Skip if the destination already exists or the same clone is running.
        if FileManager.default.fileExists(atPath: lane.url.appendingPathComponent(repo.name).path) {
            showToast("“\(repo.name)” already exists in this lane.", kind: .error); return nil
        }
        if activeClones.contains(where: { $0.laneID == lane.id && $0.name == repo.name }) { return nil }

        let job = CloneJob(laneID: lane.id, name: repo.name)
        activeClones.append(job)
        let root = LaneActions.root(of: lane)
        let cloner = RepoCloner(shell: services.shell)
        let registry = RepoRegistry(root: root)
        Task.detached(priority: .userInitiated) {
            var warning: String?
            var failure: String?
            do {
                if case .clonedWithWarnings(let s) = try cloner.clone(repo, into: lane, root: root) { warning = s }
                registry.remember(url: repo.url)
            } catch {
                failure = error.localizedDescription
            }
            await self.finishClone(job, name: repo.name, warning: warning, failure: failure)
        }
        return repo.name
    }

    private func finishClone(_ job: CloneJob, name: String, warning: String?, failure: String?) {
        activeClones.removeAll { $0.id == job.id }
        if let failure {
            showToast("Couldn’t clone “\(name)”: \(failure)", kind: .error)
        } else if let warning, !warning.isEmpty {
            showToast("Cloned “\(name)” with warnings.\n\(warning)", kind: .error)
        }
        // If the lane is on screen, reload so the finished repo replaces its
        // spinner row (the job removal already dropped the spinner).
        if stack.count == 1, currentLane?.id == job.laneID {
            reloadCurrentInPlace()
        }
    }

    /// Spinner rows for the clones running into `lane`, minus any whose repo has
    /// already surfaced in `existing` (so a mid-clone repo isn't shown twice).
    private func cloneRows(for lane: Lane, existing: [DisplayRow]) -> [DisplayRow] {
        let present = Set(existing.map(\.title))
        return activeClones
            .filter { $0.laneID == lane.id && !present.contains($0.name) }
            .map { job in
                DisplayRow(id: "cloning:\(job.id)", title: job.name, subtitle: "Cloning…",
                           icon: .repo, pathLabels: [],
                           payload: .item(BasicItem(id: "cloning:\(job.id)", title: job.name, run: { .stay })),
                           isLoading: true)
            }
    }

    private func activate(item: any Item, stayInMenu: Bool = false) {
        if let run = item.run {
            guard !isRunningAction else { return }   // ignore re-entry while one runs
            // For "New lane…", seed the name field with the current query so
            // a search that found nothing becomes the new lane's name.
            let seed = item.id == "lane:new" ? query : nil
            isRunningAction = true
            Task {
                defer { isRunningAction = false }
                // Run off the main actor so a slow script (Shell.run blocks until
                // exit) doesn't freeze the panel and the spinner can animate.
                do { honor(try await Task.detached(priority: .userInitiated) { try await run() }.value, seed: seed, stayInMenu: stayInMenu) }
                catch { showToast(error.localizedDescription, kind: .error) }
            }
        } else {
            push(item: item)
        }
    }

    private func submitInput() {
        guard let request = currentInputRequest, !isRunningAction else { return }
        let text = inputText
        isRunningAction = true
        Task {
            defer { isRunningAction = false }
            do { honor(try await Task.detached(priority: .userInitiated) { try await request.onSubmit(text) }.value) }
            catch { showToast(error.localizedDescription, kind: .error) }
        }
    }

    private func honor(_ outcome: RunOutcome, seed: String? = nil, stayInMenu: Bool = false) {
        switch outcome {
        case .dismiss:
            onClose()
        case .stay:
            break
        case .pop:
            pop()
            reloadCurrent()
        case .popToRoot:
            stack = []
            query = ""
            selection = 0
            reloadLanes()
        case .enter(let lane):
            enter(lane: lane)
        case .enterWithNotice(let lane, let notice):
            enter(lane: lane)
            showToast(notice, kind: .error)
        case .startClone(let lane, let url):
            let startedName = startClone(url: url, into: lane)   // background
            if stayInMenu {
                // ⇧Return: keep the clone menu open so several repos can be
                // queued back-to-back. No spinner shows at this depth (spinners
                // overlay only the lane's top level), so confirm with a toast;
                // clear the query and refresh so a typed URL resets and a
                // re-clone target's "already in this lane" note updates.
                if let startedName { showToast("Cloning “\(startedName)”…") }
                query = ""
                reloadCurrentInPlace()
            } else {
                enter(lane: lane)   // return to the lane; a spinner row tracks it
            }
        case .pushInput(let request):
            pushInput(request, seed: seed)
        case .pushItems(let title, let items):
            pushItems(title: title, items: items)
        }
    }

    private func pushInput(_ request: InputRequest, seed: String? = nil) {
        var level = LevelState(kind: .input(request), titleSegment: request.title)
        level.lane = currentLane
        stack.append(level)
        // A request with prefilled text (e.g. Rename) wins; otherwise fall back
        // to the seed (the carried-over search query) if there is one.
        if request.initialText.isEmpty, let seed, !seed.isEmpty {
            inputText = seed
        } else {
            inputText = request.initialText
        }
        query = ""
        selection = 0
    }

    private func pushItems(title: String, items: [any Item]) {
        var level = LevelState(kind: .items, titleSegment: title)
        level.lane = currentLane
        level.items = items
        stack.append(level)
        query = ""
        selection = 0
        let levelID = level.id
        Task { await buildIndex(levelID: levelID, token: level.loadToken) }
    }

    // MARK: - Navigation

    func enter(lane: Lane) {
        let touched = library.touch(lane)
        var level = LevelState(kind: .items, titleSegment: touched.name)
        level.lane = touched
        level.isLoading = true
        stack = [level]
        query = ""
        selection = 0
        loadLevel(level.id, from: .lane(touched), keepVisible: false)
        kickStaleRefresh(touched)
    }

    private func push(item: any Item) {
        var level = LevelState(kind: .items, titleSegment: item.title)
        level.sourceItem = item
        level.lane = currentLane
        level.isLoading = true
        level.queryFallback = item.queryFallback
        stack.append(level)
        query = ""
        selection = 0
        loadLevel(level.id, from: .children(item), keepVisible: false)
    }

    // MARK: - Loading

    /// Where a level's items come from: a lane's providers (top level) or a
    /// container item's children.
    private enum LevelSource {
        case lane(Lane)
        case children(any Item)
    }

    /// The one routine that fills a level's items, superseding any in-flight load
    /// via a fresh token.
    ///
    /// `keepVisible == false` (a fresh open / drill / ⌘R on a lane list level):
    /// show the loading state — set `isLoading`, and for a lane clear the items
    /// so the shimmer shows and provider results stream in **progressively**.
    ///
    /// `keepVisible == true` (⌘R on the open lane, post-clone reload): keep the
    /// current items on screen and swap the fresh set in **atomically** when it's
    /// ready, so the list never flashes empty.
    private func loadLevel(_ levelID: UUID, from source: LevelSource, keepVisible: Bool) {
        let token = UUID()
        mutate(levelID) {
            $0.loadToken = token
            $0.indexBuilt = false
            if !keepVisible {
                $0.isLoading = true
                if case .lane = source { $0.items = []; $0.providerResults = [] }
            }
        }
        switch source {
        case .children(let item):
            Task {
                let kids = await item.children()
                guard isCurrentToken(levelID, token) else { return }
                mutate(levelID) { $0.items = kids; $0.isLoading = false }
                await buildIndex(levelID: levelID, token: token)
            }
        case .lane(let lane):
            loadLaneProviders(levelID, lane: lane, token: token, progressive: !keepVisible)
        }
    }

    /// Run the lane's providers into `levelID`. `progressive` streams each
    /// contribution in as it returns (fresh load, with the timeout toast);
    /// otherwise all results are collected and swapped in one mutation (no
    /// flicker on an in-place reload).
    private func loadLaneProviders(_ levelID: UUID, lane: Lane, token: UUID, progressive: Bool) {
        let store = LaneStore(lane: lane)
        let providers = registry.providers
        let services = services
        Task {
            if progressive {
                var timedOut: [String] = []
                for await result in ItemLoader.load(lane: lane, store: store, services: services, providers: providers) {
                    guard isCurrentToken(levelID, token) else { return }
                    if result.timedOut { timedOut.append(result.displayName) }
                    mutate(levelID) {
                        $0.providerResults.append(result)
                        $0.items = LaneModel.merge($0.providerResults)
                    }
                }
                guard isCurrentToken(levelID, token) else { return }
                mutate(levelID) { $0.isLoading = false }
                if !timedOut.isEmpty {
                    showToast("\(timedOut.joined(separator: ", ")) timed out", kind: .error)
                }
            } else {
                var collected: [ProviderResult] = []
                for await result in ItemLoader.load(lane: lane, store: store, services: services, providers: providers) {
                    guard isCurrentToken(levelID, token) else { return }
                    collected.append(result)
                }
                guard isCurrentToken(levelID, token) else { return }
                mutate(levelID) {
                    $0.providerResults = collected
                    $0.items = LaneModel.merge(collected)
                    $0.isLoading = false
                }
            }
            await buildIndex(levelID: levelID, token: token)
        }
    }

    private func buildIndex(levelID: UUID, token: UUID) async {
        guard let level = stack.first(where: { $0.id == levelID }) else { return }
        let index = await SubtreeIndex.build(from: level.items)
        guard isCurrentToken(levelID, token) else { return }
        mutate(levelID) { $0.index = index; $0.indexBuilt = true }
    }

    /// Merge provider results into the (section, title)-sorted top level.
    private static func merge(_ results: [ProviderResult]) -> [any Item] {
        results.sorted { $0.section < $1.section }
            .flatMap { $0.items.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending } }
    }

    // MARK: - Level mutation helpers

    private func mutate(_ levelID: UUID, _ body: (inout LevelState) -> Void) {
        guard let idx = stack.firstIndex(where: { $0.id == levelID }) else { return }
        body(&stack[idx])
    }

    private func isCurrentToken(_ levelID: UUID, _ token: UUID) -> Bool {
        stack.first(where: { $0.id == levelID })?.loadToken == token
    }

    // MARK: - Toast

    func showToast(_ message: String, kind: ToastState.Kind = .info) {
        let toast = ToastState(message: message, kind: kind)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if self.toast?.id == toast.id { self.toast = nil }
        }
    }
}

// MARK: - Supporting types

struct LevelState: Identifiable {
    let id = UUID()
    enum Kind { case items; case input(InputRequest) }
    let kind: Kind
    let titleSegment: String?

    var lane: Lane?
    var sourceItem: (any Item)?
    var items: [any Item] = []
    var providerResults: [ProviderResult] = []
    var index: [IndexedItem] = []
    var indexBuilt = false
    var isLoading = false
    var loadToken = UUID()
    /// Fallback action for a non-matching query (from the container item), e.g.
    /// "Clone repo…" turning a pasted URL into a clone.
    var queryFallback: (@Sendable (String) -> (any Item)?)? = nil
}

struct DisplayRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: IconToken
    let pathLabels: [String]
    let badge: StatusBadge?
    let payload: Payload
    /// Shows a trailing spinner (e.g. a background clone in progress).
    let isLoading: Bool

    enum Payload {
        case lane(Lane)
        case item(any Item)
    }

    var isContainer: Bool {
        if case .item(let i) = payload { return i.run == nil }
        return true
    }

    /// Lane rows render with a larger title (the description) over a smaller
    /// secondary line (the folder name).
    var isLane: Bool {
        if case .lane = payload { return true }
        return false
    }

    init(id: String, title: String, subtitle: String?, icon: IconToken,
         pathLabels: [String], badge: StatusBadge? = nil, payload: Payload,
         isLoading: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.pathLabels = pathLabels
        self.badge = badge
        self.payload = payload
        self.isLoading = isLoading
    }

    init(item: any Item, pathLabels: [String]) {
        self.id = item.id + (pathLabels.isEmpty ? "" : "@" + pathLabels.joined(separator: "›"))
        self.title = item.title
        self.subtitle = item.subtitle
        self.icon = item.icon
        self.pathLabels = pathLabels
        self.badge = nil
        self.payload = .item(item)
        self.isLoading = false
    }
}

/// A background clone in progress, shown as a spinner row in its lane.
struct CloneJob: Identifiable, Equatable {
    let id = UUID()
    let laneID: UUID
    let name: String
}

struct ToastState: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let kind: Kind
    enum Kind { case info, error }
}
