//
//  ChatConfigProductCardTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — product_card decode")
struct ChatConfigProductCardTests {

    private let decoder = JSONDecoder.wire()

    @Test("product_card decodes open_label and add_to_cart.enabled")
    func decodesSettings() throws {
        let config = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "product_card": {
                "open_label": "Se produkt",
                "add_to_cart": { "enabled": true }
              }
            }
            """)

        #expect(config.productCard.openLabel == "Se produkt")
        #expect(config.productCard.addToCart.enabled == true)
    }

    @Test("missing product_card defaults to nil label and disabled cart")
    func missingDefaults() throws {
        let config = try self.decode("{\(Self.minimalDisplayTheme)}")
        #expect(config.productCard.openLabel == nil)
        #expect(config.productCard.addToCart.enabled == false)
    }

    @Test("theme product_card.button is optional")
    func optionalThemeButton() throws {
        let without = try self.decode("{\(Self.minimalDisplayTheme)}")
        #expect(without.theme.productCard.button == nil)

        let with = try self.decode("""
            {
              \(Self.minimalDisplayThemeWithButton)
            }
            """)
        #expect(with.theme.productCard.button?.backgroundColor == "#4F46E5")
        #expect(with.theme.productCard.button?.bold == true)
    }

    private func decode(_ json: String) throws -> ChatConfig {
        try self.decoder.decode(ChatConfig.self, from: Data(json.utf8))
    }

    private static let minimalDisplayTheme = """
      "display": {
        "name": "Bot",
        "avatar": { "url": null },
        "welcome_message": null,
        "subtitle": null,
        "privacy_policy_url": "https://example.com/privacy"
      },
      "theme": {
        "brand": { "primary_color": "#111111" },
        "surface": { "background_color": "#FFFFFF", "muted_text_color": "#666666" },
        "header": {
          "alignment": "left",
          "logo": { "url": "https://cdn.example.com/logo.png" },
          "button": { "background_color": "#111111", "icon_color": "#FFFFFF" }
        },
        "messages": {
          "assistant": {
            "background_color": "#F5F5F5",
            "text_color": "#111111",
            "thinking_border_gradient": []
          },
          "user": { "background_color": "#111111", "text_color": "#FFFFFF" }
        },
        "input": {
          "text_color": "#111111",
          "placeholder_color": "#999999",
          "send_button": {}
        },
        "product_card": { "discount_price_color": "#DC2626" },
        "font": {
          "ios": {
            "asset_url": "https://cdn.example.com/font.ttf",
            "sha256": "abc",
            "format": "ttf"
          }
        }
      }
    """

    private static let minimalDisplayThemeWithButton = """
      "display": {
        "name": "Bot",
        "avatar": { "url": null },
        "welcome_message": null,
        "subtitle": null,
        "privacy_policy_url": "https://example.com/privacy"
      },
      "theme": {
        "brand": { "primary_color": "#111111" },
        "surface": { "background_color": "#FFFFFF", "muted_text_color": "#666666" },
        "header": {
          "alignment": "left",
          "logo": { "url": "https://cdn.example.com/logo.png" },
          "button": { "background_color": "#111111", "icon_color": "#FFFFFF" }
        },
        "messages": {
          "assistant": {
            "background_color": "#F5F5F5",
            "text_color": "#111111",
            "thinking_border_gradient": []
          },
          "user": { "background_color": "#111111", "text_color": "#FFFFFF" }
        },
        "input": {
          "text_color": "#111111",
          "placeholder_color": "#999999",
          "send_button": {}
        },
        "product_card": {
          "discount_price_color": "#DC2626",
          "button": { "background_color": "#4F46E5", "bold": true }
        },
        "font": {
          "ios": {
            "asset_url": "https://cdn.example.com/font.ttf",
            "sha256": "abc",
            "format": "ttf"
          }
        }
      }
    """
}
