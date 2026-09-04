//
//  ConversationSnapshot.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// The published conversation: the two panes the view model zips for layout.
package struct ConversationSnapshot: Sendable, Equatable {

    package let user: [Identified<[AttributedString]>]
    package let incoming: [Identified<[ChatResponse]>]

    /// Sets the leading side when the two panes are interleaved for display.
    package let isUserInitiatedConversation: Bool

    /// The turn whose reply is currently streaming, else `nil`
    package let streamingTurnID: UUID?
}

extension ConversationSnapshot {

    /// A single conversation turn — the display-oriented union of the two panes, handed to
    /// ``ConversationView``'s content builder.
    package enum Turn: Sendable, Equatable {
        case bot([ChatResponse])
        case user([AttributedString])
    }

    /// Interleaves the two panes into render order — the leading side per round is set by
    /// `isUserInitiatedConversation` — then the single dangling turn on whichever pane is longer.
    /// Each turn carries the id its provider minted, stable across streaming and prepends.
    package var turns: [Identified<Turn>] {
        var turns: [Identified<Turn>] = []

        for (bot, user) in zip(self.incoming, self.user) {
            if self.isUserInitiatedConversation {
                turns.append(Identified(id: user.id, model: .user(user.model)))
                turns.append(Identified(id: bot.id, model: .bot(bot.model)))
            } else {
                turns.append(Identified(id: bot.id, model: .bot(bot.model)))
                turns.append(Identified(id: user.id, model: .user(user.model)))
            }
        }

        // The dangling turn is the same regardless of lead: whichever pane is longer.
        if self.incoming.count > self.user.count, let bot = self.incoming.last {
            turns.append(Identified(id: bot.id, model: .bot(bot.model)))
        } else if self.user.count > self.incoming.count, let user = self.user.last {
            turns.append(Identified(id: user.id, model: .user(user.model)))
        }

        return turns
    }
}
