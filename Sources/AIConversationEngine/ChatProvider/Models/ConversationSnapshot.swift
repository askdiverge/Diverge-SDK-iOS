//
//  ConversationSnapshot.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// The published conversation: one ordered list of turns the view renders in place.
package struct ConversationSnapshot: Sendable, Equatable {

    /// Chronological turns — oldest first. The provider builds this list in wire order so a
    /// history page whose roles do not strictly alternate still renders correctly.
    package let turns: [Identified<Turn>]

    /// The turn whose reply is currently streaming, else `nil`
    package let streamingTurnID: UUID?

    /// False once history is exhausted — the container stops asking for older pages.
    package let canLoadOlder: Bool

    /// The id of the newest user turn minted by a local send echo, else `nil`. The top-flowing
    /// layout arms its exchange from this — prepended history must not lift a stale user turn.
    package let lastSentUserTurnID: UUID?

    package init(
        turns: [Identified<Turn>],
        streamingTurnID: UUID?,
        canLoadOlder: Bool,
        lastSentUserTurnID: UUID? = nil
    ) {
        self.turns = turns
        self.streamingTurnID = streamingTurnID
        self.canLoadOlder = canLoadOlder
        self.lastSentUserTurnID = lastSentUserTurnID
    }
}

extension ConversationSnapshot {

    /// A single conversation turn — the display-oriented union of user and bot content.
    package enum Turn: Sendable, Equatable {
        case bot([ChatResponse])
        case user([UserContent])
        /// Wire `role: system` history — centred muted copy, not an assistant bubble.
        case system([ChatResponse])

        /// True for visitor turns — layout code uses this so it need not switch exhaustively
        /// when new non-user turn kinds land.
        package var isUser: Bool {
            if case .user = self { return true }
            return false
        }
    }

    /// The id of the newest user turn, else `nil`. Used by the top-flowing layout to retire an
    /// exchange when the armed user turn leaves the snapshot.
    package var lastUserTurnID: UUID? {
        self.turns.last { if case .user = $0.model { return true }; return false }?.id
    }

    /// The id of the newest bot turn, else `nil`. Used by the top-flowing layout to measure the
    /// live answer and to detect when a reply has arrived.
    package var lastBotTurnID: UUID? {
        self.turns.last {
            switch $0.model {
            case .bot: return true
            case .user, .system: return false
            }
        }?.id
    }
}
