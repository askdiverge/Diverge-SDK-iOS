//
//  ProductsCardDecodeTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("Products.Card — decode")
struct ProductsCardDecodeTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("decodes splash and add_to_cart when present")
    func decodesOptionalFields() throws {
        let products = try self.decode("""
            {
              "part_id": "part_1",
              "products": [
                {
                  "id": "prod_1",
                  "title": "Classic Tee",
                  "image_url": "https://cdn.example.com/tee.jpg",
                  "url": "https://shop.example.com/tee",
                  "splash": "60% Deal",
                  "add_to_cart": { "sku": "500108572" }
                }
              ]
            }
            """)

        #expect(products.products.count == 1)
        #expect(products.products[0].splash == "60% Deal")
        #expect(products.products[0].addToCart?.sku == "500108572")
    }

    @Test("decodes add_to_cart.url for link-mode carts")
    func decodesAddToCartUrl() throws {
        let products = try self.decode("""
            {
              "part_id": "part_1",
              "products": [
                {
                  "id": "prod_1",
                  "title": "Classic Tee",
                  "image_url": "https://cdn.example.com/tee.jpg",
                  "url": "https://shop.example.com/tee",
                  "add_to_cart": {
                    "sku": "500108572",
                    "url": "https://shop.example.com/cart/add?sku=500108572"
                  }
                }
              ]
            }
            """)

        #expect(products.products[0].addToCart?.url?.absoluteString
            == "https://shop.example.com/cart/add?sku=500108572")
    }

    @Test("splash and add_to_cart are nil when absent")
    func absentOptionals() throws {
        let products = try self.decode("""
            {
              "part_id": "part_1",
              "products": [
                {
                  "id": "prod_1",
                  "title": "Classic Tee",
                  "image_url": "https://cdn.example.com/tee.jpg",
                  "url": "https://shop.example.com/tee"
                }
              ]
            }
            """)

        #expect(products.products[0].splash == nil)
        #expect(products.products[0].addToCart == nil)
    }

    @Test("a malformed card in a batch is dropped without failing the part")
    func lossyCard() throws {
        let products = try self.decode("""
            {
              "part_id": "part_1",
              "products": [
                {
                  "id": "prod_1",
                  "title": "Keep me",
                  "image_url": "https://cdn.example.com/tee.jpg",
                  "url": "https://shop.example.com/tee"
                },
                { "id": "broken" },
                {
                  "id": "prod_2",
                  "title": "Also keep",
                  "image_url": "https://cdn.example.com/hat.jpg",
                  "url": "https://shop.example.com/hat"
                }
              ]
            }
            """)

        #expect(products.products.map(\.id) == ["prod_1", "prod_2"])
    }

    @Test("a malformed products part decodes to Part.unknown rather than throwing")
    func malformedPartIsUnknown() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"products","products":[]}"#.utf8)
        )
        #expect(part == .unknown)
    }

    private func decode(_ json: String) throws -> Products {
        try self.decoder.decode(Products.self, from: Data(json.utf8))
    }
}
