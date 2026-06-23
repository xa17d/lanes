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
        let hooks = LaneHooks(shell: services.shell, baseURL: services.ticketBaseURL)
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
        if stack.isEmpty {
            return laneRows()
        } else {
            return itemRows(for: stack[stack.count - 1])
        }
    }

    private func laneRows() -> [DisplayRow] {
        let matched: [Lane]
        if query.isEmpty {
            matched = lanes
        } else {
            matched = lanes
                .compactMap { t -> (Lane, Double)? in
                    // Match against the folder name and the description body +
                    // status text; keep the best score.
                    let nameScore = FuzzyMatcher.score(query: query, title: t.name)
                    let descScore = FuzzyMatcher.score(query, DescriptionMarkup.searchText(from: t.summary))
                    guard let best = [nameScore, descScore].compactMap({ $0 }).max() else { return nil }
                    return (t, best)
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        var rows = matched.map { t -> DisplayRow in
            // Description big, folder name smaller below; the status badge (if
            // any) is parsed out of the description.
            let parsed = DescriptionMarkup.parse(from: t.summary)
            let hasBody = !parsed.body.isEmpty
            let title = hasBody ? parsed.body : t.name
            let subtitle: String?
            if hasBody {
                subtitle = t.isArchived ? "\(t.name) · archived" : t.name
            } else {
                subtitle = t.isArchived ? "archived" : nil
            }
            return DisplayRow(id: "lane:\(t.id)", title: title, subtitle: subtitle,
                              icon: .folder, pathLabels: [], badge: parsed.badge,
                              payload: .lane(t))
        }
        // "New lane…" is always last.
        if let root = library.root {
            let item = LaneActions.newLaneItem(root: root, hooks: LaneHooks(shell: services.shell, baseURL: services.ticketBaseURL))
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
    func confirm() {
        if isInputMode { submitInput(); return }
        activateSelected()
    }

    func activateSelected() {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .lane(let t): enter(lane: t)
        case .item(let item): activate(item: item)
        }
    }

    /// Right arrow: enter a lane or a container. (Management lives inside the
    /// lane as the "Manage lane…" item, so → on a lane behaves like Enter
    /// rather than opening a separate menu.)
    func drillRight() {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .lane(let t): enter(lane: t)
        case .item(let item): activate(item: item)
        }
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
        pushInput(LaneActions.newLaneRequest(root: root, hooks: LaneHooks(shell: services.shell, baseURL: services.ticketBaseURL)), seed: query)
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
                load(children: source, intoLevel: level.id)
            } else {
                loadLaneLevel(levelID: level.id)
            }
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
        let hooks = LaneHooks(shell: services.shell, baseURL: services.ticketBaseURL)
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

    private func activate(item: any Item) {
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
                do { honor(try await Task.detached(priority: .userInitiated) { try await run() }.value, seed: seed) }
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

    private func honor(_ outcome: RunOutcome, seed: String? = nil) {
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
        loadLaneLevel(levelID: level.id)
        kickStaleRefresh(touched)
    }

    private func push(item: any Item) {
        var level = LevelState(kind: .items, titleSegment: item.title)
        level.sourceItem = item
        level.lane = currentLane
        level.isLoading = true
        stack.append(level)
        query = ""
        selection = 0
        load(children: item, intoLevel: level.id)
    }

    // MARK: - Loading

    private func loadLaneLevel(levelID: UUID) {
        guard let lane = currentLane else { return }
        let token = UUID()
        mutate(levelID) { $0.loadToken = token; $0.isLoading = true; $0.items = []; $0.providerResults = []; $0.indexBuilt = false }
        let store = LaneStore(lane: lane)
        let providers = registry.providers
        let services = services
        Task {
            let stream = ItemLoader.load(lane: lane, store: store, services: services, providers: providers)
            var timedOut: [String] = []
            for await result in stream {
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
            await buildIndex(levelID: levelID, token: token)
        }
    }

    /// Reload the current level's items *without* blanking the visible list:
    /// supersede any in-flight load, load fresh into a buffer, and swap the
    /// items in atomically when ready. Used by ⌘R so the list never flashes
    /// empty (unlike `loadLaneLevel`/`load(children:)`, which clear + shimmer).
    private func reloadCurrentInPlace() {
        guard let level = stack.last else { return }
        let levelID = level.id
        let token = UUID()
        mutate(levelID) { $0.loadToken = token }   // supersede in-flight loads; keep items
        if let source = level.sourceItem {
            Task {
                let kids = await source.children()
                guard isCurrentToken(levelID, token) else { return }
                mutate(levelID) { $0.items = kids; $0.isLoading = false }
                await buildIndex(levelID: levelID, token: token)
            }
        } else if let lane = currentLane {
            let store = LaneStore(lane: lane)
            let providers = registry.providers
            let services = services
            Task {
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
                await buildIndex(levelID: levelID, token: token)
            }
        }
    }

    private func load(children item: any Item, intoLevel levelID: UUID) {
        let token = UUID()
        mutate(levelID) { $0.loadToken = token; $0.isLoading = true; $0.indexBuilt = false }
        Task {
            let kids = await item.children()
            guard isCurrentToken(levelID, token) else { return }
            mutate(levelID) { $0.items = kids; $0.isLoading = false }
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
}

struct DisplayRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: IconToken
    let pathLabels: [String]
    let badge: StatusBadge?
    let payload: Payload

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
         pathLabels: [String], badge: StatusBadge? = nil, payload: Payload) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.pathLabels = pathLabels
        self.badge = badge
        self.payload = payload
    }

    init(item: any Item, pathLabels: [String]) {
        self.id = item.id + (pathLabels.isEmpty ? "" : "@" + pathLabels.joined(separator: "›"))
        self.title = item.title
        self.subtitle = item.subtitle
        self.icon = item.icon
        self.pathLabels = pathLabels
        self.badge = nil
        self.payload = .item(item)
    }
}

struct ToastState: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let kind: Kind
    enum Kind { case info, error }
}
