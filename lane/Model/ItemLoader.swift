//
//  ItemLoader.swift
//  lane
//
//  Streaming loader for a lane's top level: runs all providers concurrently,
//  yielding each provider's contribution as it returns, with a per-provider
//  timeout (cancel the task, drop its contribution, flag the timeout).
//

import Foundation

nonisolated enum ItemLoader {
    static let defaultTimeout: Duration = .seconds(3)

    /// Stream of per-provider results. Consumers merge and sort by
    /// (section, title); the stream finishes when every provider has either
    /// returned or timed out.
    static func load(
        lane: Lane,
        store: LaneStore,
        services: Services,
        providers: [any LaneProvider],
        timeout: Duration = defaultTimeout
    ) -> AsyncStream<ProviderResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: ProviderResult.self) { group in
                    for provider in providers {
                        group.addTask {
                            await runOne(provider, lane: lane, store: store,
                                         services: services, timeout: timeout)
                        }
                    }
                    for await result in group {
                        continuation.yield(result)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Race: Sendable {
        case done([any Item])
        case timedOut
    }

    private static func runOne(
        _ provider: any LaneProvider,
        lane: Lane,
        store: LaneStore,
        services: Services,
        timeout: Duration
    ) async -> ProviderResult {
        let outcome: Race = await withTaskGroup(of: Race.self) { group in
            group.addTask {
                .done(await provider.items(for: lane, store: store, services: services))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        switch outcome {
        case .done(let items):
            return ProviderResult(section: provider.section,
                                  displayName: provider.displayName,
                                  items: items, timedOut: false)
        case .timedOut:
            return ProviderResult(section: provider.section,
                                  displayName: provider.displayName,
                                  items: [], timedOut: true)
        }
    }
}
