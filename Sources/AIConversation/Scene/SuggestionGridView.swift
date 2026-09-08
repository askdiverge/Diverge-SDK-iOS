//
//  SuggestionGridView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-04.
//

import SwiftUI
import AIConversationEngine

/// Lays out a bot response's suggestions as a two-column grid. Tapping a card delivers
/// its `promptText` via `onSelect`.
struct SuggestionGridView: View {

    let cards: [Suggestions.Card]
    let onSelect: (String) -> Void

    var body: some View {
        CardGrid(itemCount: self.cards.count) { index in
            let card = self.cards[index]
            Button {
                self.onSelect(card.promptText)
            } label: {
                SuggestionCardView(card: card)
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
            .accessibilityLabel(Self.accessibilityLabel(for: card))
            .accessibilityHint(Self.accessibilityHint)
        }
    }
}

// MARK: - Accessibility contract

extension SuggestionGridView {

    /// VoiceOver label: title, then description when present — the image is decorative.
    static func accessibilityLabel(for card: Suggestions.Card) -> String {
        if let description = card.description, !description.isEmpty {
            return "\(card.title). \(description)"
        }
        return card.title
    }

    /// VoiceOver hint: what activating the card does.
    static var accessibilityHint: String {
        L10n.suggestionSendHint.string
    }
}
