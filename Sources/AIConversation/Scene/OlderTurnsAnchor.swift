//
//  OlderTurnsAnchor.swift
//  AIConversation
//

import Foundation

/// Remembers the turn the reader was at when they asked for older turns, so the list can return
/// to it once those turns land above.
struct OlderTurnsAnchor {

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

    /// The turn to return to now the list went from `old` to `new`, once a new first turn shows
    /// that older turns landed. A page that joined the first turn leaves the reader in place.
    mutating func landing(from old: [UUID], to new: [UUID]) -> UUID? {
        guard let turnID = self.turnID, old != new else { return nil }
        self.turnID = nil
        return new.first != old.first && new.contains(turnID) ? turnID : nil
    }
}
