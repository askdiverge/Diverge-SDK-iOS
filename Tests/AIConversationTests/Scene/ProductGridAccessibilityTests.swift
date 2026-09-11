//
//  ProductGridAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ProductGridView — accessibility contract")
@MainActor
struct ProductGridAccessibilityTests {

    @Test("label is the title alone when there is no description or splash")
    func labelTitleOnly() {
        let card = self.card(title: "Classic Tee", description: nil, splash: nil)
        #expect(ProductGridView.accessibilityLabel(for: card) == "Classic Tee")
    }

    @Test("label joins title, description and splash")
    func labelTitleDescriptionSplash() {
        let card = self.card(title: "Classic Tee", description: "Soft cotton", splash: "60% Deal")
        #expect(
            ProductGridView.accessibilityLabel(for: card)
                == "Classic Tee. Soft cotton. 60% Deal"
        )
    }

    @Test("open and add-to-cart hints are wired to non-empty string resources")
    func hintsAreWired() {
        #expect(!ProductGridView.openAccessibilityHint.isEmpty)
        #expect(!ProductGridView.addToCartAccessibilityHint.isEmpty)
    }

    @Test("resolved open label uses config text or the localised fallback")
    func resolvedOpenLabel() {
        #expect(ProductGridView.resolvedOpenLabel("Se produkt") == "Se produkt")
        #expect(ProductGridView.resolvedOpenLabel("   ") == L10n.productOpen.string)
        #expect(ProductGridView.resolvedOpenLabel(nil) == L10n.productOpen.string)
    }

    @Test("cart is offered with a host hook or a link-mode cart URL, only when config enables cart")
    func shouldOfferCart() {
        let withSku = self.card(title: "Classic Tee", description: nil, splash: nil, sku: "SKU-TEE-001")
        let withLinkCart = self.card(
            title: "Classic Tee",
            description: nil,
            splash: nil,
            sku: "SKU-TEE-001",
            cartUrl: URL(string: "https://shop.example.com/cart/add")!
        )
        let withoutSku = self.card(title: "Classic Tee", description: nil, splash: nil, sku: nil)
        let hook: @MainActor (AIChat.ProductSelection) -> Void = { _ in }

        #expect(ProductGridView.shouldOfferCart(for: withSku, cartEnabled: true, onAddToCart: hook) == true)
        #expect(ProductGridView.shouldOfferCart(for: withLinkCart, cartEnabled: true, onAddToCart: nil) == true)
        #expect(ProductGridView.shouldOfferCart(for: withoutSku, cartEnabled: true, onAddToCart: hook) == false)
        #expect(ProductGridView.shouldOfferCart(for: withSku, cartEnabled: true, onAddToCart: nil) == false)
        // `/config` off wins over both modes — a stale link pattern must not leak a cart button.
        #expect(ProductGridView.shouldOfferCart(for: withSku, cartEnabled: false, onAddToCart: hook) == false)
        #expect(ProductGridView.shouldOfferCart(for: withLinkCart, cartEnabled: false, onAddToCart: nil) == false)
    }

    @Test("image ratio is decided once per grid so mixed rows stay aligned")
    func gridWideImageAspectRatio() {
        let withSku = self.card(title: "Classic Tee", description: nil, splash: nil, sku: "SKU-TEE-001")
        let withoutSku = self.card(title: "Classic Hat", description: nil, splash: nil, sku: nil)
        let hook: @MainActor (AIChat.ProductSelection) -> Void = { _ in }

        #expect(
            ProductGridView.imageAspectRatio(for: [withSku, withoutSku], cartEnabled: true, onAddToCart: hook)
                == ProductGridView.compactImageAspectRatio
        )
        #expect(
            ProductGridView.imageAspectRatio(for: [withoutSku, withoutSku], cartEnabled: true, onAddToCart: hook)
                == ProductGridView.defaultImageAspectRatio
        )
        #expect(
            ProductGridView.imageAspectRatio(for: [withSku, withoutSku], cartEnabled: false, onAddToCart: hook)
                == ProductGridView.defaultImageAspectRatio
        )
    }

    @Test("product copy exists in every locale")
    func catalogCoverage() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "product.open", "product.openHint", "product.addToCart", "product.addToCartHint"
        ])
    }

    private func card(
        title: String,
        description: String?,
        splash: String?,
        sku: String? = nil,
        cartUrl: URL? = nil
    ) -> Products.Card {
        Products.Card(
            id: "p1",
            title: title,
            description: description,
            imageUrl: URL(string: "https://cdn.example.com/p1.jpg"),
            price: nil,
            originalPrice: nil,
            splash: splash,
            url: URL(string: "https://shop.example.com/p1")!,
            addToCart: sku.map { Products.AddToCart(sku: $0, url: cartUrl) }
        )
    }
}
