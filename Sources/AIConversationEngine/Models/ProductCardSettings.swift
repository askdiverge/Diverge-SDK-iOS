//
//  ProductCardSettings.swift
//  AIConversation
//

import Foundation

/// Product-card CTA label and add-to-cart availability from `GET /api/v1/chat/config`.
/// [API ref](https://docs.dialoge.ai/api#model/chatbot-product-card-settings)
package struct ProductCardSettings: Decodable, Sendable, Equatable {

    /// Dashboard CTA label. `nil` → client uses its own localised fallback.
    package let openLabel: String?
    package let addToCart: AddToCart

    package init(openLabel: String? = nil, addToCartEnabled: Bool = false) {
        let trimmed = openLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openLabel = (trimmed?.isEmpty == false) ? trimmed : nil
        self.addToCart = AddToCart(enabled: addToCartEnabled)
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .openLabel)
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openLabel = (trimmed?.isEmpty == false) ? trimmed : nil
        self.addToCart =
            try container.decodeIfPresent(AddToCart.self, forKey: .addToCart) ?? AddToCart(enabled: false)
    }

    private enum CodingKeys: String, CodingKey {
        case openLabel, addToCart
    }

    package struct AddToCart: Decodable, Sendable, Equatable {
        package let enabled: Bool
    }
}
