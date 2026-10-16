//
//  ChatResponse.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// Incoming display models, agnostic to whether they arrived as a part or assembled deltas.
/// `text` folds all inline styling (bold/strike/link).
/// `products` reuses the wire `Products.Card` as-is — it's already display-shaped.
/// `form` reuses the normalised ``ConversationForm`` — markers arrive whole, as a `part` event
/// live or as a part in history, never as deltas.
/// `table` massages the wire model into folded columns + rectangular rows (`TableContent`).
/// `requestHumanAgent` is the handoff prompt card; the view model posts a marker handover.
/// `livechatNote` is an SDK-minted queue / joined / ended divider, not wire-derived.
/// `systemNote` is wire `role: system` copy, shown centred and muted.
/// `placeholder` is FE-minted, never wire-derived — a pre-delta thinking indicator the
/// first streamed response overwrites in place.
package enum ChatResponse: Sendable, Equatable {
    case text(AttributedString)
    case products([Products.Card])
    case form(ConversationForm)
    case table(TableContent)
    case requestHumanAgent(RequestHumanAgent)
    case livechatNote(LivechatNote)
    case systemNote(AttributedString)
    case placeholder(AttributedString)
}
