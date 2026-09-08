//
//  RatingSession.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Remembers whether this `AIChat` instance has already submitted a rating.
///
/// Held by ``AIChat`` (not the view model) so `hasRated` survives the host dismissing and
/// re-presenting the chat — `makeView()` builds a fresh view model each call. In-memory only:
/// the SDK has no conversation identity to key a disk file by, the server accepts overwrites,
/// and the web widget keeps the same flag in React state.
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
