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
    @Published var selection: Int = 0
    @Published var toast: ToastState?
    @Published var includeArchived = false

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

    var currentLevel: LevelState? { stack.last }
    var currentTrack: Track? { stack.first?.track }

    var breadcrumb: [String] { stack.compactMap(\.titleSegment) }

    // MARK: - Rows

    var rows: [DisplayRow] {
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
        return matched.map { t in
            DisplayRow(id: "track:\(t.id)", title: t.name,
                       subtitle: t.isArchived ? "archived" : nil,
                       icon: .folder, pathLabels: [], payload: .track(t))
        }
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

    func activateSelected() {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .track(let t): enter(track: t)
        case .item(let item): activate(item: item)
        }
    }

    /// Right arrow: drill into containers / track-management. For items this
    /// matches Return; track-management menu arrives in Phase 7.
    func drillRight() {
        guard let row = selectedRow else { return }
        switch row.payload {
        case .track(let t): enter(track: t)
        case .item(let item): activate(item: item)
        }
    }

    func escape() {
        if !query.isEmpty {
            query = ""
        } else if stack.isEmpty {
            onClose()
        } else {
            pop()
        }
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
            runLeaf(run)
        } else {
            push(item: item)
        }
    }

    private func runLeaf(_ run: @escaping @Sendable () async throws -> RunOutcome) {
        Task {
            do {
                let outcome = try await run()
                switch outcome {
                case .dismiss: onClose()
                case .pop: pop()
                case .stay: break
                }
            } catch {
                showToast(error.localizedDescription, kind: .error)
            }
        }
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
    enum Kind { case items }
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
