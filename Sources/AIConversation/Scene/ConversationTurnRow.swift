//
//  ConversationTurnRow.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// One turn in ``ConversationTopFlowingList``, aligned to its side and reporting its height.
///
/// The list lays every turn out, so a turn's height is the one it measures; a product grid in
/// it still lays out its cards as they come on screen. A turn's views are built again only when
/// ``==`` says the row changed, so an update of a streaming reply builds the reply's views and
/// keeps the views of the other turns.
struct ConversationTurnRow<Content: View>: View {

    let turn: Identified<ConversationSnapshot.Turn>
    /// Whether the turn's reply is streaming, which `content` draws differently.
    let isStreaming: Bool
    /// Whether the turn is the newest bot turn, the one the list sizes its buffer against. The
    /// list decides it when it builds the row, and `onHeightChange` acts on that decision.
    let isNewestBotTurn: Bool
    @ViewBuilder let content: (Identified<ConversationSnapshot.Turn>) -> Content
    /// Called with the turn's height when it is first laid out and each time it changes.
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        self.content(self.turn)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { self.onHeightChange($0) }
            .frame(maxWidth: .infinity, alignment: self.alignment)
            .id(self.turn.id)
    }

    private var alignment: Alignment {
        switch self.turn.model {
        case .bot: .topLeading
        case .user: .topTrailing
        }
    }
}

// MARK: - Equatable

extension ConversationTurnRow: @MainActor Equatable {

    /// Two rows are the same when they show the same turn in the same role. A row keeps the
    /// `content` and `onHeightChange` it was built with for as long as that holds, through the
    /// new closures the list passes on every update.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.turn == rhs.turn
            && lhs.isStreaming == rhs.isStreaming
            && lhs.isNewestBotTurn == rhs.isNewestBotTurn
    }
}
