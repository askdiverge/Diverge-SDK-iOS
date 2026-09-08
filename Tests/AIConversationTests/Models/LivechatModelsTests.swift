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
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    @Test("ChatConfig defaults livechat when the block is absent")
    func configAbsentLivechatDefaults() throws {
        let json = """
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
        }
        """.data(using: .utf8)!
        let config = try decoder.decode(ChatConfig.self, from: json)
        #expect(config.livechat.enabled == false)
        #expect(config.livechat.availabilityStatus == .offline)
        #expect(config.livechat.showLivechatLogo == true)
    }

    @Test("LivechatSettings decodes enabled live config")
    func settingsDecode() throws {
        let json = """
        {
          "enabled": true,
          "configured": true,
          "availability_status": "live",
          "availability_reason": "always_on",
          "show_livechat_logo": true,
          "attachments_enabled": true,
          "max_attachment_size_bytes": 5242880
        }
        """.data(using: .utf8)!
        let settings = try decoder.decode(LivechatSettings.self, from: json)
        #expect(settings.isAvailable)
        #expect(settings.availabilityStatus == .live)
        #expect(settings.availabilityReason == .alwaysOn)
        #expect(settings.attachmentsEnabled == true)
        #expect(settings.maxAttachmentSizeBytes == 5_242_880)
    }

    @Test("missing attachments_enabled fails closed; missing max size uses 5 MiB")
    func settingsAttachmentsDefaultFailClosed() throws {
        let json = """
        {
          "enabled": true,
          "configured": true,
          "availability_status": "live",
          "availability_reason": "always_on",
          "show_livechat_logo": true
        }
        """.data(using: .utf8)!
        let settings = try decoder.decode(LivechatSettings.self, from: json)
        #expect(settings.attachmentsEnabled == false)
        #expect(settings.maxAttachmentSizeBytes == 5_242_880)
    }

    @Test("request_human_agent marker decodes")
    func humanAgentMarker() throws {
        let json = """
        { "type": "request_human_agent", "part_id": "part_human_1" }
        """.data(using: .utf8)!
        let part = try decoder.decode(Part.self, from: json)
        guard case .requestHumanAgent(let marker) = part else {
            Issue.record("expected requestHumanAgent")
            return
        }
        #expect(marker.partId == "part_human_1")
    }

    @Test("LivechatState and LivechatMessage decode")
    func stateAndMessage() throws {
        let stateJSON = """
        {
          "status": "active",
          "active_agent": {
            "agent_id": "00000000-0000-4000-8000-0000000000a1",
            "display_name": "Alice",
            "avatar_url": null
          },
          "is_agent_typing": true,
          "agent_joined_at": "2025-06-15T14:31:00Z",
          "closed_by": null,
          "feedback": { "status": "not_available", "submitted_at": null }
        }
        """.data(using: .utf8)!
        let state = try decoder.decode(LivechatState.self, from: stateJSON)
        #expect(state.status == .active)
        #expect(state.activeAgent?.displayName == "Alice")
        #expect(state.isAgentTyping)
        #expect(state.stateVersion == nil)

        let withVersion = """
        {
          "status": "waiting",
          "is_agent_typing": false,
          "feedback": { "status": "not_available" },
          "state_version": 7
        }
        """.data(using: .utf8)!
        let versioned = try decoder.decode(LivechatState.self, from: withVersion)
        #expect(versioned.stateVersion == 7)
        #expect(versioned.status == .waiting)

        let msgJSON = """
        {
          "message_id": "livechat_msg_2",
          "role": "agent",
          "agent": {
            "agent_id": "00000000-0000-4000-8000-0000000000a1",
            "display_name": "Alice",
            "avatar_url": null
          },
          "parts": [{ "type": "unknown_part" }],
          "created_at": "2025-06-15T14:31:00Z",
          "sequence_number": 2
        }
        """.data(using: .utf8)!
        let message = try decoder.decode(LivechatMessage.self, from: msgJSON)
        #expect(message.sequenceNumber == 2)
        #expect(message.role == .agent)
        #expect(message.agent?.displayName == "Alice")
    }

    @Test("lastBotTurnID counts agent turns")
    func lastBotTurnCountsAgent() {
        let agent = LivechatAgent(agentId: "a", displayName: "Alice")
        let turns: [Identified<ConversationSnapshot.Turn>] = [
            Identified(model: .user([.text(AttributedString("hi"))])),
            Identified(model: .agent(agent, [.text(AttributedString("hello"))])),
        ]
        let snapshot = ConversationSnapshot(turns: turns, streamingTurnID: nil, canLoadOlder: false)
        #expect(snapshot.lastBotTurnID == turns[1].id)
        #expect(turns[0].model.isUser)
        #expect(!turns[1].model.isUser)
    }
}
