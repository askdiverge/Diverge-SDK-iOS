//
//  SuggestionCardView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-04.
//

import SwiftUI
import AIConversationEngine

/// A single suggestion surfaced in a bot response. Tapping it sends `promptText` as the
/// visitor's next message.
struct SuggestionCardView: View {

    let card: Suggestions.Card

    var body: some View {
        MediaCardBody(
            imageURL: self.card.imageUrl,
            title: self.card.title,
            description: self.card.description
        )
    }
}
