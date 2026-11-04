//
//  RatingSession.swift
//  AIConversation
//

import Foundation

/// Remembers whether the current conversation has been rated, so closing again doesn't ask twice.
///
/// ``AIChat`` holds it, because each presentation builds a new view model. It lives in memory for
/// as long as its holder: one `AIChat`, or the shared configuration for instances minted from it.
@MainActor
final class RatingSession {

    private(set) var hasRated = false

    func markRated() {
        self.hasRated = true
    }

    /// Cleared on conversation reset and visitor-data deletion.
    func clear() {
        self.hasRated = false
    }
}
