//
//  ChatAppearanceProductButtonTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatAppearance — product button theme")
struct ChatAppearanceProductButtonTests {

    @Test("a bad product button hex keeps the palette and leaves background nil")
    func badButtonHexIsLenient() throws {
        let decoder = JSONDecoder.wire()
        let config = try decoder.decode(ChatConfig.self, from: Data("""
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
                  "logo": { "url": "https://example.com/logo.png" },
                  "button": { "background_color": "#4F46E5", "icon_color": "#FFFFFF" }
                },
                "messages": {
                  "assistant": {
                    "background_color": "#F3F4F6",
                    "text_color": "#111827",
                    "thinking_border_gradient": []
                  },
                  "user": { "background_color": "#4F46E5", "text_color": "#FFFFFF" }
                },
                "input": {
                  "text_color": "#111827",
                  "placeholder_color": "#9CA3AF",
                  "send_button": {}
                },
                "product_card": {
                  "discount_price_color": "#DC2626",
                  "button": { "background_color": "not-a-color", "bold": false }
                },
                "font": {
                  "ios": {
                    "asset_url": "https://example.com/font.ttf",
                    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "format": "ttf"
                  }
                }
              }
            }
            """.utf8))

        let appearance = ChatAppearance(config, fontFamily: nil)
        #expect(appearance.theme.productButtonBackground == nil)
        #expect(appearance.theme.productButtonBold == false)
        // Required palette still parsed (not dumped to .default).
        let expectedAccent = try #require(Color(hex: "#4F46E5"))
        #expect(appearance.theme.accent == expectedAccent)
    }
}
