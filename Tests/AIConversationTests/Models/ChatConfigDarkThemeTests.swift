//
//  ChatConfigDarkThemeTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — dark_theme")
struct ChatConfigDarkThemeTests {

    private let decoder = JSONDecoder.wire()

    @Test("absent dark_theme decodes equal to theme")
    func absentDarkThemeEqualsTheme() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.lightOnlyJSON.utf8))
        #expect(config.darkTheme == config.theme)
        #expect(config.theme.surface.backgroundColor == "#FFFFFF")
    }

    @Test("a distinct dark_theme decodes independently")
    func distinctDarkTheme() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.withDarkJSON.utf8))
        #expect(config.theme.surface.backgroundColor == "#FFFFFF")
        #expect(config.darkTheme.surface.backgroundColor == "#1C1C1E")
        #expect(config.darkTheme.messages.assistant.backgroundColor == "#2C2C2E")
        #expect(config.darkTheme.brand.primaryColor == "#818CF8")
        #expect(config.theme.brand.primaryColor == "#4F46E5")
    }

    @Test("a truncated dark_theme fails the whole config decode")
    func truncatedDarkThemeFailsDecode() {
        #expect(throws: DecodingError.self) {
            try self.decoder.decode(ChatConfig.self, from: Data(Self.truncatedDarkJSON.utf8))
        }
    }

    @Test("unknown keys on a complete dark_theme are ignored")
    func extraDarkThemeKeysAreIgnored() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.extraKeyDarkJSON.utf8))
        #expect(config.darkTheme.surface.backgroundColor == "#1C1C1E")
    }

    // MARK: - Fixtures

    private static let lightThemeBlock = """
        {
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

    private static let darkThemeBlock = """
        {
          "brand": { "primary_color": "#818CF8" },
          "surface": { "background_color": "#1C1C1E", "muted_text_color": "#9BA1A6" },
          "header": {
            "alignment": "left",
            "logo": { "url": "https://example.com/logo.png" },
            "button": { "background_color": "#2C2C2E", "icon_color": "#FFFFFF" }
          },
          "messages": {
            "assistant": {
              "background_color": "#2C2C2E",
              "text_color": "#F2F2F7",
              "thinking_border_gradient": []
            },
            "user": { "background_color": "#818CF8", "text_color": "#FFFFFF" }
          },
          "input": {
            "text_color": "#F2F2F7",
            "placeholder_color": "#8E8E93",
            "background_color": "#2C2C2E",
            "send_button": {}
          },
          "product_card": { "discount_price_color": "#FF6B6B" },
          "font": {
            "ios": {
              "asset_url": "https://example.com/font.ttf",
              "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "format": "ttf"
            }
          }
        }
        """

    private static var lightOnlyJSON: String {
        """
        {
          "display": {
            "name": "Bot",
            "avatar": { "url": null },
            "welcome_message": null,
            "subtitle": null,
            "privacy_policy_url": "https://example.com/privacy"
          },
          "theme": \(lightThemeBlock)
        }
        """
    }

    private static var withDarkJSON: String {
        wrap(theme: lightThemeBlock, dark: darkThemeBlock)
    }

    private static var truncatedDarkJSON: String {
        wrap(theme: lightThemeBlock, dark: "{}")
    }

    private static var extraKeyDarkJSON: String {
        let withExtra = String(darkThemeBlock.dropLast()) + ",\n          \"unknown_future_key\": true\n        }"
        return wrap(theme: lightThemeBlock, dark: withExtra)
    }

    private static func wrap(theme: String, dark: String) -> String {
        """
        {
          "display": {
            "name": "Bot",
            "avatar": { "url": null },
            "welcome_message": null,
            "subtitle": null,
            "privacy_policy_url": "https://example.com/privacy"
          },
          "theme": \(theme),
          "dark_theme": \(dark)
        }
        """
    }
}
