//
//  ChatResponse.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// Assistant display models, agnostic to whether it arrived as a part or assembled deltas.
/// `text` folds all inline styling (bold/strike/link)
/// `products` reuses the wire `Products.Card` as-is — it's already display-shaped.
/// `table` massages the wire model  into folded columns + rectangular rows (`TableContent`).
/// `placeholder` is FE-minted, never wire-derived — a pre-delta thinking indicator the
/// first streamed response overwrites in place.
package enum ChatResponse: Sendable, Equatable {
    case text(AttributedString)
    case products([Products.Card])
    case table(TableContent)
    case placeholder(AttributedString)
}
