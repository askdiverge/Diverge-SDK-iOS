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
    package let products: [Card]
}

extension Products {

    /// [API ref](https://docs.dialoge.ai/api#model/product-card)
    package struct Card: Decodable, Sendable, Equatable {

        package let id: String
        package let title: String
        package let description: String?
        package let imageUrl: URL
        package let price: Price?
        package let originalPrice: Price?
        package let url: URL
    }

    /// Price with amount and ISO 4217 currency code.
    /// [API ref](https://docs.dialoge.ai/api#model/product-price)
    package struct Price: Decodable, Sendable, Equatable {
        package let amount: Double
        package let currency: String
    }
}
