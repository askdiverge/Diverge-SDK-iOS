//
//  ProductCardView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-10.
//

import SwiftUI
import AIConversationEngine

/// A single product surfaced in a bot response.
///
/// Discount is inferred from the data, not carried as styling: when `originalPrice` is present the
/// card is on sale, so the current price is tinted `discountPriceColor` and the original is struck through.
struct ProductCardView: View {

    @Environment(\.appearance) private var appearance

    let card: Products.Card

    private var isDiscounted: Bool {
        self.card.originalPrice != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            Color.clear
                .aspectRatio(0.7, contentMode: .fit)
                .overlay {
                    RemoteImageView(url: self.card.imageUrl) { result in
                        switch result {
                        case .success(let loaded):
                            loaded.resizable().scaledToFill()
                        case .failure:
                            // TODO: replace with a real image-failure view
                            EmptyView()
                        }
                    } placeholder: {
                        ProgressView()
                            .tint(self.appearance.theme.accent)
                    }
                }
                .background(self.appearance.theme.botSurface)
                .clipped()

            Text(self.card.title)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(self.appearance.theme.primaryText)

            if let description = self.card.description {
                Text(description)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.secondaryText)
            }

            self.priceRow

            Spacer(minLength: 0)
        }
    }

    // Flip the row to a stack when the prices don't fit side by side, so the row reflows as a
    // whole instead of each price wrapping onto its own line independently.
    private var priceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: self.appearance.spacing.units(1)) {
                self.prices
            }

            VStack(alignment: .leading, spacing: self.appearance.spacing.units(1)) {
                self.prices
            }
        }
    }

    @ViewBuilder
    private var prices: some View {
        if let price = self.card.price {
            Text(price.formatted)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(
                    self.isDiscounted ? self.appearance.theme.discountPrice : self.appearance.theme.primaryText
                )
        }

        if let originalPrice = self.card.originalPrice {
            Text(originalPrice.struckThrough)
                .font(self.appearance.font(size: 12))
                .foregroundStyle(self.appearance.theme.secondaryText)
        }
    }
}

private extension Products.Price {

    var formatted: String {
        self.amount.formatted(.currency(code: self.currency))
    }

    var struckThrough: AttributedString {
        var attributed = AttributedString(self.formatted)
        attributed.strikethroughStyle = .single
        return attributed
    }
}
