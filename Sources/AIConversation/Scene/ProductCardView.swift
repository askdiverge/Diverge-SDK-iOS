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
    /// Resolved open-product CTA label — the grid applies the L10n fallback.
    var openLabel: String
    /// When false, the open capsule is omitted so the grid can lay it out beside add-to-cart.
    var showsOpenCTA = true

    private var isDiscounted: Bool {
        self.card.originalPrice != nil
    }

    var body: some View {
        MediaCardBody(
            imageURL: self.card.imageUrl,
            aspectRatio: self.showsOpenCTA ? 0.7 : 1.0,
            title: self.card.title,
            description: self.card.description
        ) {
            if let splash = self.card.splash?.trimmingCharacters(in: .whitespacesAndNewlines),
               !splash.isEmpty {
                Text(splash)
                    .font(self.appearance.font(size: 11, weight: .bold))
                    .foregroundStyle(self.appearance.theme.accentForeground)
                    .padding(.horizontal, self.appearance.spacing.units(2))
                    .padding(.vertical, self.appearance.spacing.units(1))
                    .background(self.appearance.theme.accent, in: Capsule())
                    .padding(self.appearance.spacing.units(2))
                    .accessibilityHidden(true)
            }
        } footer: {
            self.priceRow

            if self.showsOpenCTA {
                AccentCapsuleLabel(
                    title: self.openLabel,
                    fillsWidth: true,
                    background: self.appearance.theme.productButtonBackground,
                    bold: self.appearance.theme.productButtonBold
                )
            }
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
