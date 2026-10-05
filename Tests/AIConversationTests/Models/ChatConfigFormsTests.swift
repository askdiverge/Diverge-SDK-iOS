//
//  ChatConfigFormsTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatConfig — forms decode")
struct ChatConfigFormsTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("forms decodes livechat_waiting and picks the first waiting id")
    func decodesWaitingForm() throws {
        let config = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "forms": [
                {
                  "form_id": "sessionStart",
                  "name": "Start",
                  "trigger": "session_start",
                  "override_targets": [],
                  "submit_actions": []
                },
                {
                  "form_id": "livechatWaitingContact",
                  "name": "Waiting contact",
                  "trigger": "livechat_waiting",
                  "override_targets": [],
                  "submit_actions": []
                }
              ]
            }
            """)

        #expect(config.forms.count == 2)
        #expect(config.forms[1].trigger == .livechatWaiting)
        #expect(config.livechatWaitingFormId == "livechatWaitingContact")
    }

    @Test("missing forms defaults empty; malformed rows are dropped")
    func missingAndLossy() throws {
        let empty = try self.decode("{\(Self.minimalDisplayTheme)}")
        #expect(empty.forms.isEmpty)
        #expect(empty.livechatWaitingFormId == nil)

        let lossy = try self.decode("""
            {
              \(Self.minimalDisplayTheme),
              "forms": [
                { "form_id": "keep", "trigger": "livechat_waiting" },
                { "trigger": "livechat_waiting" },
                { "form_id": "also", "trigger": "llm" }
              ]
            }
            """)
        #expect(lossy.forms.map(\.formId) == ["keep", "also"])
        #expect(lossy.livechatWaitingFormId == "keep")
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
