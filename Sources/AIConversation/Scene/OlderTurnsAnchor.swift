//
//  OlderTurnsAnchor.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Remembers the turn the reader was at when they asked for older turns, so the list can return
/// to it once those turns land above.
struct OlderTurnsAnchor {

    /// What a change to the list means for the load in flight.
    enum Landing: Equatable {
        /// No page landed: nothing was asked for, or the change came from elsewhere.
        case none
        /// The page landed. `returnTo` is the reader's turn when older turns landed above it, and
        /// `nil` when the page joined the first turn or the conversation was replaced.
        case landed(returnTo: UUID?)
    }

    private var turnID: UUID?

    /// A load is in flight, or its turns haven't reached the list yet.
    var isArmed: Bool {
        self.turnID != nil
    }

    mutating func arm(at turnID: UUID?) {
        self.turnID = turnID
    }

    /// The load refused or found nothing, so no turns are on their way.
    mutating func disarm() {
        self.turnID = nil
    }

    /// Follows the list from `old` to `new`. A page changes the list at its top, by adding turns
    /// above the first or by joining it, so a change further down, such as a reply or an agent
    /// message, leaves the anchor waiting for the page.
    mutating func landing(
        from old: [Identified<ConversationSnapshot.Turn>],
        to new: [Identified<ConversationSnapshot.Turn>]
    ) -> Landing {
        guard let turnID = self.turnID, new.first != old.first else { return .none }
        self.turnID = nil
        let landedAbove = new.first?.id != old.first?.id && new.contains { $0.id == turnID }
        return .landed(returnTo: landedAbove ? turnID : nil)
    }
}
