//
//  LivechatNote.swift
//  AIConversationEngine
//

import Foundation

/// A session-local divider line minted by the SDK on livechat transitions (not wire-derived).
package struct LivechatNote: Sendable, Equatable {

    package enum Kind: Sendable, Equatable {
        /// Visitor entered the queue.
        case queued
        /// An agent joined; carries the display name for copy.
        case agentJoined(displayName: String)
        /// The livechat session ended.
        case ended
    }

    package let kind: Kind

    package init(kind: Kind) {
        self.kind = kind
    }
}
