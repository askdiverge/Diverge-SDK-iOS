//
//  LivechatNote.swift
//  AIConversationEngine
//

import Foundation

/// A session-local divider line the SDK mints on livechat transitions. It is not wire-derived;
/// the conversation shows it between turns so the visitor can see when they joined the queue,
/// when an agent joined, and when the session ended.
package struct LivechatNote: Sendable, Equatable {

    package enum Kind: Sendable, Equatable {
        /// The visitor entered the queue.
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
