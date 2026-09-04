//
//  ProductGridView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-10.
//

import SwiftUI
import AIConversationEngine

/// Lays out a bot response's products as a two-column grid.
struct ProductGridView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let cards: [Products.Card]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: self.appearance.spacing.units(2)), GridItem(.flexible())],
            alignment: .leading,
            spacing: self.appearance.spacing.units(3)
        ) {
            ForEach(self.cards, id: \.id) { card in
                ProductCardView(card: card)
                    .contentShape(.rect)
                    .onTapGesture { self.openURL(card.url) }
            }
        }
    }
}
