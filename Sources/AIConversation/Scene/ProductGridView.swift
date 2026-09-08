//
//  ProductGridView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-10.
//

import SwiftUI
import AIConversationEngine

/// Lays out a bot response's products as a two-column grid. The whole card opens the product
/// URL; an optional sibling add-to-cart button sits above the open CTA when the host callback
/// is set **and** the card carries a sku (siblings, not nested — cart first so it stays clear
/// of the composer).
struct ProductGridView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let cards: [Products.Card]
    var openLabel: String?
    /// Host cart hook, already gated by config `product_card.add_to_cart.enabled`. Cards
    /// without a sku still omit the cart button.
    var onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)?

    var body: some View {
        CardGrid(itemCount: self.cards.count) { index in
            let card = self.cards[index]
            let offersCart = Self.shouldOfferCart(for: card, onAddToCart: self.onAddToCart)
            let openTitle = Self.resolvedOpenLabel(self.openLabel)
            VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
                Button {
                    self.openURL(card.url)
                } label: {
                    ProductCardView(
                        card: card,
                        openLabel: openTitle,
                        // When cart is offered, the open capsule moves into the sibling row below.
                        showsOpenCTA: !offersCart
                    )
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityLabel(Self.accessibilityLabel(for: card))
                .accessibilityValue(openTitle)
                .accessibilityHint(Self.openAccessibilityHint)
                .accessibilityIdentifier("product.\(index)")

                if offersCart, let addToCart = card.addToCart {
                    let sku = addToCart.sku.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sku.isEmpty {
                        // Cart first so it sits above the composer on tall cards; open capsule
                        // remains a sibling (not nested) for VoiceOver.
                        VStack(spacing: self.appearance.spacing.units(2)) {
                            Button {
                                if let cartUrl = addToCart.url {
                                    self.openURL(cartUrl)
                                } else if let onAddToCart {
                                    onAddToCart(
                                        AIChat.ProductSelection(
                                            id: card.id,
                                            sku: sku,
                                            title: card.title,
                                            url: card.url
                                        )
                                    )
                                }
                            } label: {
                                AccentCapsuleLabel(
                                    title: L10n.productAddToCart.string,
                                    fillsWidth: true,
                                    background: self.appearance.theme.productButtonBackground,
                                    bold: self.appearance.theme.productButtonBold
                                )
                            }
                            .buttonStyle(.plain)
                            .minimumTouchTarget()
                            .accessibilityLabel(L10n.productAddToCart.string)
                            .accessibilityHint(Self.addToCartAccessibilityHint)
                            .accessibilityIdentifier("product.addToCart.\(index)")

                            Button {
                                self.openURL(card.url)
                            } label: {
                                AccentCapsuleLabel(
                                    title: openTitle,
                                    fillsWidth: true,
                                    background: self.appearance.theme.productButtonBackground,
                                    bold: self.appearance.theme.productButtonBold
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Accessibility contract

extension ProductGridView {

    /// VoiceOver label: title, then description when present — the image is decorative.
    static func accessibilityLabel(for card: Products.Card) -> String {
        var parts = [card.title]
        if let description = card.description, !description.isEmpty {
            parts.append(description)
        }
        if let splash = card.splash?.trimmingCharacters(in: .whitespacesAndNewlines), !splash.isEmpty {
            parts.append(splash)
        }
        return parts.joined(separator: ". ")
    }

    static var openAccessibilityHint: String {
        L10n.productOpenHint.string
    }

    static var addToCartAccessibilityHint: String {
        L10n.productAddToCartHint.string
    }

    /// Dashboard CTA label, or the localised "View product" fallback when null / blank.
    static func resolvedOpenLabel(_ openLabel: String?) -> String {
        let trimmed = openLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.productOpen.string : trimmed
    }

    /// Cart sibling when the host hooked add-to-cart or the card carries a link-mode cart URL.
    static func shouldOfferCart(
        for card: Products.Card,
        onAddToCart: (@MainActor (AIChat.ProductSelection) -> Void)?
    ) -> Bool {
        let sku = card.addToCart?.sku.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sku.isEmpty else { return false }
        return card.addToCart?.url != nil || onAddToCart != nil
    }
}
