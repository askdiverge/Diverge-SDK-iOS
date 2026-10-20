//
//  LivechatModelsTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("Livechat models")
struct LivechatModelsTests {

    private let decoder: JSONDecoder = {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return jsonDecoder
    }()

    @Test("ChatConfig defaults livechat when the block is absent")
    func configAbsentLivechatDefaults() throws {
        let config = try self.decodeConfig(extra: "")

        #expect(config.livechat == .serverDefaults)
        #expect(config.forms.isEmpty)
        #expect(config.livechatWaitingFormId == nil)
    }

    @Test("LivechatConfig decodes enabled live config")
    func settingsDecode() throws {
        let json = Data("""
        {
          "enabled": true,
          "configured": true,
          "availability_status": "live",
          "availability_reason": "always_on",
          "show_livechat_logo": true,
          "attachments_enabled": true,
          "max_attachment_size_bytes": 5242880
        }
        """.utf8)
        let settings = try decoder.decode(LivechatConfig.self, from: json)
        #expect(settings.isAvailable)
        #expect(settings.availabilityStatus == .live)
        #expect(settings.availabilityReason == .alwaysOn)
        #expect(settings.attachmentsEnabled == true)
        #expect(settings.maxAttachmentSizeBytes == 5_242_880)
    }

    @Test("missing attachments_enabled fails closed; missing max size uses 5 MiB")
    func settingsAttachmentsDefaultFailClosed() throws {
        let json = Data("""
        {
          "enabled": true,
          "configured": true,
          "availability_status": "live",
          "availability_reason": "always_on",
          "show_livechat_logo": true
        }
        """.utf8)
        let settings = try decoder.decode(LivechatConfig.self, from: json)
        #expect(settings.attachmentsEnabled == false)
        #expect(settings.maxAttachmentSizeBytes == 5_242_880)
    }

    @Test("request_human_agent marker decodes")
    func humanAgentMarker() throws {
        let json = Data("""
        { "type": "request_human_agent", "part_id": "part_human_1" }
        """.utf8)
        let part = try decoder.decode(Part.self, from: json)
        guard case .requestHumanAgent(let marker) = part else {
            Issue.record("expected requestHumanAgent")
            return
        }
        #expect(marker.partId == "part_human_1")
    }

    @Test("config forms drop malformed rows and pick the first waiting-room form")
    func configForms() throws {
        let config = try self.decodeConfig(extra: """
          ,
          "forms": [
            { "form_id": "start", "name": null, "trigger": "session_start" },
            { "name": "No id", "trigger": "livechat_waiting" },
            { "form_id": "waiting", "name": "Waiting", "trigger": "livechat_waiting" },
            { "form_id": "later", "name": null, "trigger": "livechat_waiting" }
          ]
        """)

        #expect(config.forms.map(\.formId) == ["start", "waiting", "later"])
        #expect(config.livechatWaitingFormId == "waiting")
    }

    @Test("a history message from an agent carries the agent identity")
    func agentMessage() throws {
        let message = try decoder.decode(Message.self, from: Data("""
        {
          "message_id": "m_2",
          "role": "agent",
          "agent": {
            "agent_id": "00000000-0000-4000-8000-0000000000a1",
            "display_name": "Alice",
            "avatar_url": null
          },
          "parts": [],
          "created_at": "2026-01-01T00:00:00Z"
        }
        """.utf8))

        #expect(message.role == .agent)
        #expect(message.agent?.displayName == "Alice")
        #expect(message.agent?.avatarUrl == nil)
    }

    @Test("a data: attachment URL is accepted without a base URL")
    func dataURLAttachment() throws {
        let part = try decoder.decode(Part.self, from: Data("""
        { "type": "file", "filename": "a.png", "url": "DATA:image/png;base64,QQ==" }
        """.utf8))

        guard case .file(let file) = part else {
            Issue.record("expected a file part, got \(part)")
            return
        }
        #expect(file.url.scheme?.lowercased() == "data")
    }

    @Test("url_expires_at parses with and without fractional seconds")
    func attachmentExpiry() {
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

        #expect(AttachmentURL.isExpired("2025-12-31T23:59:59Z", at: now))
        #expect(AttachmentURL.isExpired("2025-12-31T23:59:59.500Z", at: now))
        #expect(!AttachmentURL.isExpired("2026-01-01T00:00:01Z", at: now))
        #expect(!AttachmentURL.isExpired(nil, at: now))
        #expect(!AttachmentURL.isExpired("not a date", at: now))
    }

    // MARK: - Fixtures

    /// Decodes a minimal `/config` body, with `extra` appended after `theme`.
    private func decodeConfig(extra: String) throws -> ChatConfig {
        try self.decoder.decode(ChatConfig.self, from: Data("""
        {
          "display": {
            "name": "Bot",
            "avatar": { "url": null },
            "welcome_message": null,
            "subtitle": null,
            "privacy_policy_url": "https://example.com/privacy"
          },
          "theme": {
            "brand": { "primary_color": "#000000" },
            "surface": { "background_color": "#FFFFFF", "muted_text_color": "#666666" },
            "header": {
              "alignment": "center",
              "logo": { "url": "https://example.com/logo.png" },
              "button": { "background_color": "#EEE", "icon_color": "#111" }
            },
            "messages": {
              "assistant": {
                "background_color": "#F3F4F6",
                "text_color": "#111",
                "thinking_border_gradient": ["#FFF", "#000"]
              },
              "user": { "background_color": "#4F46E5", "text_color": "#FFF" }
            },
            "input": {
              "text_color": "#111",
              "placeholder_color": "#999",
              "send_button": {}
            },
            "product_card": { "discount_price_color": "#C00" },
            "font": {
              "ios": {
                "asset_url": "https://example.com/font.ttf",
                "sha256": "abc",
                "format": "ttf"
              }
            }
          }
        \(extra)
        }
        """.utf8))
    }
}
