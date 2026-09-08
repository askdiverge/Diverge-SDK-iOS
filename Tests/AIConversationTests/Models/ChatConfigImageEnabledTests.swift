//
//  ChatConfigImageEnabledTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — image_enabled decode")
struct ChatConfigImageEnabledTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("image_enabled true and false decode")
    func decodesFlag() throws {
        let enabled = try self.decode("""
            { \(Self.minimalDisplayTheme), "image_enabled": true }
            """)
        let disabled = try self.decode("""
            { \(Self.minimalDisplayTheme), "image_enabled": false }
            """)

        #expect(enabled.imageEnabled)
        #expect(!disabled.imageEnabled)
    }

    @Test("missing image_enabled defaults to true so older APIs keep host-gated attach")
    func missingDefaultsTrue() throws {
        let config = try self.decode("{ \(Self.minimalDisplayTheme) }")
        #expect(config.imageEnabled)
    }

    private func decode(_ json: String) throws -> ChatConfig {
        try self.decoder.decode(ChatConfig.self, from: Data(json.utf8))
    }

    /// Minimal `/config` body that satisfies the required display + theme shape.
    private static let minimalDisplayTheme = """
        "display": {
          "name": "Bot",
          "avatar": { "url": null },
          "welcome_message": null,
          "subtitle": null,
          "privacy_policy_url": "https://example.com/privacy"
        },
        "theme": {
          "brand": { "primary_color": "#4F46E5" },
          "surface": { "background_color": "#FFFFFF", "muted_text_color": "#6B7280" },
          "header": {
            "alignment": "left",
            "logo": { "url": "https://example.com/logo.png" },
            "button": { "background_color": "#4F46E5", "icon_color": "#FFFFFF" }
          },
          "messages": {
            "assistant": {
              "background_color": "#F3F4F6",
              "text_color": "#111827",
              "avatar_size": "small",
              "border_color": null,
              "thinking_border_gradient": ["#4F46E5"]
            },
            "user": {
              "background_color": "#4F46E5",
              "text_color": "#FFFFFF",
              "border_color": null
            }
          },
          "input": {
            "text_color": "#111827",
            "placeholder_color": "#9CA3AF",
            "background_color": "#FFFFFF",
            "border_color": "#E5E7EB",
            "send_button": { "icon_color": "#4F46E5" }
          },
          "product_card": { "discount_price_color": "#DC2626" },
          "font": {
            "ios": {
              "asset_url": "https://example.com/font.ttf",
              "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "format": "ttf"
            }
          }
        }
        """
}
