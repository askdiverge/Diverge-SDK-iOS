//
//  Products.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// A collection of product cards surfaced from the product catalog.
/// [API ref](https://docs.dialoge.ai/api#model/products-content)
package struct Products: Decodable, Sendable, Equatable {

    package let partId: String
    /// One malformed card is dropped rather than aborting the whole part / SSE stream.
    package let products: [Card]

    package init(partId: String, products: [Card]) {
        self.partId = partId
        self.products = products
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.products =
            try container.decodeIfPresent(LossyArray<Card>.self, forKey: .products)?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case partId, products
    }
}

extension Products {

    /// [API ref](https://docs.dialoge.ai/api#model/product-card)
    package struct Card: Decodable, Sendable, Equatable {

        package let id: String
        package let title: String
        package let description: String?
        /// Soft-fail decode — a malformed `image_url` must not abort the SSE stream.
        package let imageUrl: URL?
        package let price: Price?
        package let originalPrice: Price?
        /// Optional badge overlay on the product image (e.g. "60% Deal").
        package let splash: String?
        package let url: URL
        /// Present when a `{{add_to_cart:SKU}}` marker (or JSON field) supplied a sku.
        package let addToCart: AddToCart?

        package init(
            id: String,
            title: String,
            description: String?,
            imageUrl: URL?,
            price: Price?,
            originalPrice: Price?,
            splash: String? = nil,
            url: URL,
            addToCart: AddToCart? = nil
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.imageUrl = imageUrl
            self.price = price
            self.originalPrice = originalPrice
            self.splash = splash
            self.url = url
            self.addToCart = addToCart
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.title = try container.decode(String.self, forKey: .title)
            self.description = try container.decodeIfPresent(String.self, forKey: .description)
            self.price = try container.decodeIfPresent(Price.self, forKey: .price)
            self.originalPrice = try container.decodeIfPresent(Price.self, forKey: .originalPrice)
            self.splash = try container.decodeIfPresent(String.self, forKey: .splash)
            self.url = try container.decode(URL.self, forKey: .url)
            self.addToCart = try container.decodeIfPresent(AddToCart.self, forKey: .addToCart)
            let raw = try container.decode(String.self, forKey: .imageUrl)
            self.imageUrl = URL(string: raw)
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, description, imageUrl, price, originalPrice, splash, url, addToCart
        }
    }

    /// Add-to-cart identity for a product card.
    /// [API ref](https://docs.dialoge.ai/api#model/product-add-to-cart)
    package struct AddToCart: Decodable, Sendable, Equatable {
        package let sku: String
        /// Link-mode cart URL. When present, clients open this instead of invoking a host callback.
        package let url: URL?

        package init(sku: String, url: URL? = nil) {
            self.sku = sku
            self.url = url
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.sku = try container.decode(String.self, forKey: .sku)
            if let raw = try container.decodeIfPresent(String.self, forKey: .url) {
                self.url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                self.url = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case sku, url
        }
    }

    /// Price with amount and ISO 4217 currency code.
    /// [API ref](https://docs.dialoge.ai/api#model/product-price)
    package struct Price: Decodable, Sendable, Equatable {
        package let amount: Double
        package let currency: String
    }
}
