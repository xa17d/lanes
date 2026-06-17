//
//  LaneModel.swift
//  lane
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
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @Published var lanes: [Lane] = []
    @Published var stack: [LevelState] = []
    @Published var query: String = "" { didSet { selection = 0 } }
    @Published var inputText: String = ""
    @Published var selection: Int = 0
    @Published var toast: ToastState?
    @Published var includeArchived = false
    @Published var panelAppeared = false

    init(library: LaneLibrary, services: Services, registry: ProviderRegistry) {
        self.library = library
        self.services = services
        self.registry = registry
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
        }
        if !rows.indices.contains(selection) { selection = 0 }
    }

    func reloadLanes() {
        lanes = library.lanes(includeArchived: includeArchived)
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
                    let descScore = FuzzyMatcher.score(query, StatusBadge.searchText(from: t.summary))
                    guard let best = [nameScore, descScore].compactMap({ $0 }).max() else { return nil }
                    return (t, best)
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        var rows = matched.map { t -> DisplayRow in
            // Description big, folder name smaller below; the status badge (if
            // any) is parsed out of the description.
            let parsed = StatusBadge.parse(from: t.summary)
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
            let item = LaneActions.newLaneItem(root: root, hooks: LaneHooks(shell: services.shell))
            rows.append(DisplayRow(item: item, pathLabels: []))
        }
        return rows
    }

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
        pushInput(LaneActions.newLaneRequest(root: root, hooks: LaneHooks(shell: services.shell)), seed: query)
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

    /// ⌘R: reload the current level *and* re-run the update-lane-description
    /// hook so descriptions reflect their latest state.
    func refresh() {
        reloadCurrent()
        refreshDescriptions()
    }

    /// Re-run `update-lane-description` off the main thread, then fold the new
    /// descriptions back in. In the lane list this refreshes every listed lane;
    /// inside a lane it refreshes just that lane (updating the header).
    private func refreshDescriptions() {
        guard let root = library.root else { return }
        let hooks = LaneHooks(shell: services.shell)
        if stack.isEmpty {
            let targets = lanes
            Task.detached {
                for lane in targets {
                    if let desc = hooks.description(for: lane, root: root) {
                        _ = try? LaneFS.setSummary(lane, to: desc)
                    }
                }
                await self.reloadLanes()
            }
        } else if let lane = currentLane {
            Task.detached {
                guard let desc = hooks.description(for: lane, root: root),
                      let updated = try? LaneFS.setSummary(lane, to: desc) else { return }
                await self.applyLaneUpdate(updated)
            }
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
            // For "New lane…", seed the name field with the current query so
            // a search that found nothing becomes the new lane's name.
            let seed = item.id == "lane:new" ? query : nil
            Task {
                do { honor(try await run(), seed: seed) }
                catch { showToast(error.localizedDescription, kind: .error) }
            }
        } else {
            push(item: item)
        }
    }

    private func submitInput() {
        guard let request = currentInputRequest else { return }
        let text = inputText
        Task {
            do { honor(try await request.onSubmit(text)) }
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
            .flatMap { $0.items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
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
