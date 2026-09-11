//
//  ChatConfigStartPromptsTests.swift
//  AIConversationTests
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — start_prompts decode")
struct ChatConfigStartPromptsTests {

    private let decoder = JSONDecoder.wire()

    @Test("start_prompts decodes prompt_text and nullable url_pattern")
    func decodesPrompts() throws {
        let config = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "start_prompts": [
                { "prompt_text": "Track my order", "url_pattern": null },
                { "prompt_text": "Find a size", "url_pattern": "/products" }
              ]
            }
            """)

        #expect(config.startPrompts.count == 2)
        #expect(config.startPrompts[0].promptText == "Track my order")
        #expect(config.startPrompts[0].urlPattern == nil)
        #expect(config.startPrompts[1].promptText == "Find a size")
        #expect(config.startPrompts[1].urlPattern == "/products")
    }

    @Test("missing start_prompts decodes as an empty array")
    func missingDefaultsEmpty() throws {
        let config = try self.decode("{\(Self.minimalDisplayTheme)}")
        #expect(config.startPrompts.isEmpty)
    }

    @Test("a malformed start_prompts element is dropped without failing the config")
    func lossyElement() throws {
        let config = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "start_prompts": [
                { "prompt_text": "Keep me" },
                { "url_pattern": "/products" },
                { "prompt_text": "Also keep", "url_pattern": null }
              ]
            }
            """)

        #expect(config.startPrompts.map(\.promptText) == ["Keep me", "Also keep"])
    }

    @Test("blank or whitespace prompt_text is dropped")
    func blankPromptTextDropped() throws {
        let config = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "start_prompts": [
                { "prompt_text": "Keep me" },
                { "prompt_text": "   " },
                { "prompt_text": "", "url_pattern": "/products" },
                { "prompt_text": "Also keep", "url_pattern": null }
              ]
            }
            """)

        #expect(config.startPrompts.map(\.promptText) == ["Keep me", "Also keep"])
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
