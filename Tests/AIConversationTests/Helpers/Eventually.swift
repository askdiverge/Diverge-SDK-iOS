//
//  Eventually.swift
//  AIConversationTests
//

import Testing

/// Polls `condition` on the main actor until it holds, failing after ~2 s. Snapshot state
/// reaches the view model through an observing `Task`, so a hop is expected in view-model tests.
@MainActor
func eventually(
    _ condition: @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition did not hold in time", sourceLocation: sourceLocation)
}
