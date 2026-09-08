//
//  ChatAppearanceColorSchemeTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatAppearance — color scheme")
struct ChatAppearanceColorSchemeTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("with(colorScheme: .dark) serves the dark palette")
    func darkSchemeServesDark() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.withDarkJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        let dark = appearance.with(colorScheme: .dark)
        let light = appearance.with(colorScheme: .light)

        let expectedDarkBg = try #require(Color(hex: "#1C1C1E"))
        let expectedLightBg = try #require(Color(hex: "#FFFFFF"))
        #expect(dark.theme.background == expectedDarkBg)
        #expect(light.theme.background == expectedLightBg)
        #expect(dark.colorScheme == .dark)
        #expect(light.colorScheme == .light)
    }

    @Test("an unparseable required dark hex yields the parsed light palette, not .default")
    func brokenDarkFallsBackToLight() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.brokenDarkJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        let expectedLightAccent = try #require(Color(hex: "#4F46E5"))
        #expect(appearance.light.accent == expectedLightAccent)
        #expect(appearance.dark.accent == expectedLightAccent)
        #expect(appearance.dark.background == appearance.light.background)
        // Not the SDK default black accent.
        #expect(appearance.dark.accent != ChatAppearance.Theme.default.accent)
    }

    @Test("an unparseable light hex yields .default for light; a valid dark still parses")
    func brokenLightYieldsDefaultLight() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.brokenLightJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        #expect(appearance.light.accent == ChatAppearance.Theme.default.accent)
        let expectedDarkAccent = try #require(Color(hex: "#818CF8"))
        #expect(appearance.dark.accent == expectedDarkAccent)
    }

    @Test("absent dark_theme keeps light == dark")
    func absentDarkKeepsLightEqualDark() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.lightOnlyJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        #expect(appearance.light.background == appearance.dark.background)
        let expected = try #require(Color(hex: "#FFFFFF"))
        #expect(appearance.with(colorScheme: .dark).theme.background == expected)
        #expect(appearance.hasDistinctDarkPalette == false)
        #expect(appearance.with(colorScheme: .dark).chromeColorScheme == .light)
    }

    @Test("a distinct dark_theme reports distinct chrome")
    func distinctDarkReportsChrome() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.withDarkJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        #expect(appearance.hasDistinctDarkPalette)
        #expect(appearance.with(colorScheme: .dark).chromeColorScheme == .dark)
        #expect(appearance.with(colorScheme: .light).chromeColorScheme == .light)
    }

    @Test("a broken dark hex is not a distinct dark palette")
    func brokenDarkIsNotDistinct() throws {
        let config = try self.decoder.decode(ChatConfig.self, from: Data(Self.brokenDarkJSON.utf8))
        let appearance = ChatAppearance(config, fontFamily: nil)
        #expect(appearance.hasDistinctDarkPalette == false)
        #expect(appearance.with(colorScheme: .dark).chromeColorScheme == .light)
    }

    // MARK: - Fixtures

    private static func theme(
        primary: String,
        background: String,
        muted: String,
        assistantBg: String,
        assistantText: String,
        userBg: String,
        inputText: String,
        placeholder: String,
        discount: String
    ) -> String {
        """
        {
          "brand": { "primary_color": "\(primary)" },
          "surface": { "background_color": "\(background)", "muted_text_color": "\(muted)" },
          "header": {
            "alignment": "left",
            "logo": { "url": "https://example.com/logo.png" },
            "button": { "background_color": "\(primary)", "icon_color": "#FFFFFF" }
          },
          "messages": {
            "assistant": {
              "background_color": "\(assistantBg)",
              "text_color": "\(assistantText)",
              "thinking_border_gradient": []
            },
            "user": { "background_color": "\(userBg)", "text_color": "#FFFFFF" }
          },
          "input": {
            "text_color": "\(inputText)",
            "placeholder_color": "\(placeholder)",
            "send_button": {}
          },
          "product_card": { "discount_price_color": "\(discount)" },
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

    private static let lightTheme = theme(
        primary: "#4F46E5",
        background: "#FFFFFF",
        muted: "#6B7280",
        assistantBg: "#F3F4F6",
        assistantText: "#111827",
        userBg: "#4F46E5",
        inputText: "#111827",
        placeholder: "#9CA3AF",
        discount: "#DC2626"
    )

    private static let darkTheme = theme(
        primary: "#818CF8",
        background: "#1C1C1E",
        muted: "#9BA1A6",
        assistantBg: "#2C2C2E",
        assistantText: "#F2F2F7",
        userBg: "#818CF8",
        inputText: "#F2F2F7",
        placeholder: "#8E8E93",
        discount: "#FF6B6B"
    )

    private static let brokenDarkTheme = theme(
        primary: "not-a-color",
        background: "#1C1C1E",
        muted: "#9BA1A6",
        assistantBg: "#2C2C2E",
        assistantText: "#F2F2F7",
        userBg: "#818CF8",
        inputText: "#F2F2F7",
        placeholder: "#8E8E93",
        discount: "#FF6B6B"
    )

    private static let brokenLightTheme = theme(
        primary: "not-a-color",
        background: "#FFFFFF",
        muted: "#6B7280",
        assistantBg: "#F3F4F6",
        assistantText: "#111827",
        userBg: "#4F46E5",
        inputText: "#111827",
        placeholder: "#9CA3AF",
        discount: "#DC2626"
    )

    private static func wrap(theme: String, dark: String? = nil) -> String {
        var body = """
        {
          "display": {
            "name": "Bot",
            "avatar": { "url": null },
            "welcome_message": null,
            "subtitle": null,
            "privacy_policy_url": "https://example.com/privacy"
          },
          "theme": \(theme)
        """
        if let dark {
            body += ",\n          \"dark_theme\": \(dark)"
        }
        body += "\n        }"
        return body
    }

    private static var lightOnlyJSON: String { wrap(theme: lightTheme) }
    private static var withDarkJSON: String { wrap(theme: lightTheme, dark: darkTheme) }
    private static var brokenDarkJSON: String { wrap(theme: lightTheme, dark: brokenDarkTheme) }
    private static var brokenLightJSON: String { wrap(theme: brokenLightTheme, dark: darkTheme) }
}
