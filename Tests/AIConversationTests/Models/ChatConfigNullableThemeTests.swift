//
//  ChatConfigNullableThemeTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — nullable logo url and font sha256")
struct ChatConfigNullableThemeTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("null header logo url and font sha256 decode like the live /config mapper")
    func decodesNullLogoAndFontSha() throws {
        let config = try self.decoder.decode(
            ChatConfig.self,
            from: Data(Self.payload.utf8)
        )
        #expect(config.theme.header.logo.url == nil)
        #expect(config.theme.font.ios.sha256 == nil)
        #expect(config.theme.font.ios.assetUrl.absoluteString == "https://example.com/font.ttf")
    }

    private static let payload = """
        {
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
              "logo": { "url": null },
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
                "sha256": null,
                "format": "truetype"
              }
            }
          }
        }
        """
}
