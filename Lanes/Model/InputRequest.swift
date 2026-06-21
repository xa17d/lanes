//
//  InputRequest.swift
//  Lanes
//
//  Describes a single-field input level (Link Jira ticket…, New lane…,
//  Rename…). The submit handler performs the side effect and returns the
//  navigation outcome.
//

import Foundation

nonisolated struct InputRequest: Sendable {
    let title: String
    let placeholder: String
    var initialText: String = ""
    let onSubmit: @Sendable (String) async throws -> RunOutcome
}

nonisolated struct InputError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
