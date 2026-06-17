//
//  LaneModel.swift
//  lane
//
//  The navigation + search view model. Owns the level stack, selection, and
//  query, and drives streaming loads. Level 0 (the track list) is implicit:
//  when `stack` is empty we show tracks; otherwise we show `stack.last`.
//

import Foundation
import Combine

@MainActor
final class LaneModel: ObservableObject {
    let library: TrackLibrary
    let services: Services
    let registry: ProviderRegistry
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    @Published var tracks: [Track] = []
    @Published var stack: [LevelState] = []
    @Published var query: String = "" { didSet { selection = 0 } }
    @Published var inputText: String = ""
    @Published var selection: Int = 0
    @Published var toast: ToastState?
    @Published var includeArchived = false
    @Published var panelAppeared = false

    init(library: TrackLibrary, services: Services, registry: ProviderRegistry) {
        self.library = library
        self.services = services
        self.registry = registry
    }

    // MARK: - Lifecycle

    /// Called every time the panel opens: re-scan from disk and reset to level 0.
    func reset() {
        stack = []
        query = ""
        selection = 0
        reloadTracks()
    }

    func reloadTracks() {
        tracks = library.tracks(includeArchived: includeArchived)
    }

    /// Toggle archived tracks in the level-0 list (so they can be unarchived).
    func toggleArchived() {
        guard stack.isEmpty else { return }
        includeArchived.toggle()
        selection = 0
        reloadTracks()
    }

    var currentLevel: LevelState? { stack.last }
    var currentTrack: Track? { stack.first?.track }

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
            return trackRows()
        } else {
            return itemRows(for: stack[stack.count - 1])
        }
    }

    private func trackRows() -> [DisplayRow] {
        let matched: [Track]
        if query.isEmpty {
            matched = tracks
        } else {
            matched = tracks
                .compactMap { t -> (Track, Double)? in
                    FuzzyMatcher.score(query: query, title: t.name).map { (t, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        var rows = matched.map { t in
            DisplayRow(id: "track:\(t.id)", title: t.name,
                       subtitle: t.isArchived ? "archived" : nil,
                       icon: .folder, pathLabels: [], payload: .track(t))
        }
        // "New track…" is always last.
        if let root = library.root {
            rows.append(DisplayRow(item: TrackActions.newTrackItem(root: root), pathLabels: []))
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
        case .track(let t): enter(track: t)
        case .item(let item): activate(item: item)
        }
    }

    /// Right arrow: enter containers, or reveal the track-management menu.
    func drillRight() {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .track(let t): showManagement(for: t)
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

    func newTrack() {
        guard let root = library.root else {
            showToast("Set a root folder in Settings (⌘,) first.", kind: .error)
            return
        }
        // Carry whatever was typed in the search field into the name field as
        // a starting suggestion.
        pushInput(TrackActions.newTrackRequest(root: root), seed: query)
    }

    private func showManagement(for track: Track) {
        guard let root = library.root else { return }
        let items = TrackActions.managementItems(for: track, root: root, apps: services.apps)
        pushItems(title: track.name, items: items)
    }

    func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        query = ""
        selection = 0
        if stack.isEmpty { reloadTracks() }
    }

    func reloadCurrent() {
        if stack.isEmpty {
            reloadTracks()
        } else if let level = stack.last {
            if let source = level.sourceItem {
                load(children: source, intoLevel: level.id)
            } else {
                loadTrackLevel(levelID: level.id)
            }
        }
    }

    private func activate(item: any Item) {
        if let run = item.run {
            // For "New track…", seed the name field with the current query so
            // a search that found nothing becomes the new track's name.
            let seed = item.id == "track:new" ? query : nil
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
            reloadTracks()
        case .enter(let track):
            enter(track: track)
        case .pushInput(let request):
            pushInput(request, seed: seed)
        case .pushItems(let title, let items):
            pushItems(title: title, items: items)
        }
    }

    private func pushInput(_ request: InputRequest, seed: String? = nil) {
        var level = LevelState(kind: .input(request), titleSegment: request.title)
        level.track = currentTrack
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
        level.track = currentTrack
        level.items = items
        stack.append(level)
        query = ""
        selection = 0
        let levelID = level.id
        Task { await buildIndex(levelID: levelID, token: level.loadToken) }
    }

    // MARK: - Navigation

    func enter(track: Track) {
        let touched = library.touch(track)
        var level = LevelState(kind: .items, titleSegment: touched.name)
        level.track = touched
        level.isLoading = true
        stack = [level]
        query = ""
        selection = 0
        loadTrackLevel(levelID: level.id)
    }

    private func push(item: any Item) {
        var level = LevelState(kind: .items, titleSegment: item.title)
        level.sourceItem = item
        level.track = currentTrack
        level.isLoading = true
        stack.append(level)
        query = ""
        selection = 0
        load(children: item, intoLevel: level.id)
    }

    // MARK: - Loading

    private func loadTrackLevel(levelID: UUID) {
        guard let track = currentTrack else { return }
        let token = UUID()
        mutate(levelID) { $0.loadToken = token; $0.isLoading = true; $0.items = []; $0.providerResults = []; $0.indexBuilt = false }
        let store = TrackStore(track: track)
        let providers = registry.providers
        let services = services
        Task {
            let stream = ItemLoader.load(track: track, store: store, services: services, providers: providers)
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

    var track: Track?
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
    let payload: Payload

    enum Payload {
        case track(Track)
        case item(any Item)
    }

    var isContainer: Bool {
        if case .item(let i) = payload { return i.run == nil }
        return true
    }

    init(id: String, title: String, subtitle: String?, icon: IconToken, pathLabels: [String], payload: Payload) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.pathLabels = pathLabels
        self.payload = payload
    }

    init(item: any Item, pathLabels: [String]) {
        self.id = item.id + (pathLabels.isEmpty ? "" : "@" + pathLabels.joined(separator: "›"))
        self.title = item.title
        self.subtitle = item.subtitle
        self.icon = item.icon
        self.pathLabels = pathLabels
        self.payload = .item(item)
    }
}

struct ToastState: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let kind: Kind
    enum Kind { case info, error }
}
