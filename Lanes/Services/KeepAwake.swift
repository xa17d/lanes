//
//  KeepAwake.swift
//  Lanes
//
//  A manual "keep the Mac awake" toggle (like `caffeinate -i`) for long agent
//  runs. Holds a single ProcessInfo activity that disables idle *system* sleep
//  while active (the display may still sleep); releasing it restores normal
//  sleep. Off at launch — never persisted, so it can't silently drain the
//  battery after a restart. Toggled from the menu bar and the launcher, which
//  both observe this one instance.
//

import Foundation
import Combine

@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isActive = false
    private var token: (any NSObjectProtocol)?

    func toggle() { isActive ? disable() : enable() }

    func enable() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Keep awake while agents are working")
        isActive = true
    }

    func disable() {
        if let token { ProcessInfo.processInfo.endActivity(token) }
        token = nil
        isActive = false
    }
}
