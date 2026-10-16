//
//  LivechatFixtures.swift
//  AIConversationTests
//

import Foundation
@testable import AIConversationEngine

enum LivechatFixtures {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// A state with no agent at `version`.
    static func state(_ status: LivechatState.Status, version: Int?) -> LivechatState {
        LivechatState(
            status: status,
            activeAgent: nil,
            isAgentTyping: false,
            agentJoinedAt: nil,
            closedBy: nil,
            feedback: LivechatState.Feedback(status: .notAvailable),
            stateVersion: version
        )
    }

    /// An `active` state with `agentName` as the agent.
    static func activeState(agentName: String) throws -> LivechatState {
        try self.decoder.decode(LivechatState.self, from: Data("""
        {
          "environment": "live",
          "status": "active",
          "platform": "mobile_app",
          "active_agent": { "agent_id": "a", "display_name": "\(agentName)", "avatar_url": null },
          "is_agent_typing": false,
          "language": null,
          "feedback": { "status": "not_available", "submitted_at": null },
          "updated_at": null,
          "agent_joined_at": "2026-01-01T00:00:00Z",
          "closed_at": null,
          "closed_by": null,
          "closed_by_agent_id": null
        }
        """.utf8))
    }

    /// A one-paragraph text message at `sequence`.
    static func message(
        _ id: String,
        role: Message.Role,
        text: String = "text",
        sequence: Int64 = 1,
        createdAt: String = "2026-01-01T00:00:00Z"
    ) -> LivechatMessage {
        LivechatMessage(
            messageId: id,
            role: role,
            agent: nil,
            parts: [.richText(RichText(partId: "p_\(id)", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: createdAt,
            sequenceNumber: sequence
        )
    }

    /// A file part named `order.pdf`, decoded the way the wire sends it.
    static func file(
        url: String = "https://cdn.example.com/order.pdf",
        attachmentId: String? = nil,
        sizeBytes: Int? = nil,
        expiresAt: String? = nil
    ) throws -> MessageFile {
        var json: [String: Any] = ["filename": "order.pdf", "url": url]
        json["attachment_id"] = attachmentId
        json["size_bytes"] = sizeBytes
        json["url_expires_at"] = expiresAt
        return try self.decoder.decode(MessageFile.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// An agent message at `sequence` carrying `file` as its only part.
    static func fileMessage(_ id: String, file: MessageFile, sequence: Int64 = 1) -> LivechatMessage {
        LivechatMessage(
            messageId: id,
            role: .agent,
            agent: nil,
            parts: [.file(file)],
            createdAt: "2026-01-01T00:00:00Z",
            sequenceNumber: sequence
        )
    }

    /// The messages one `syncLivechat` call returns from ``MockChatService``.
    struct Page: Sendable {
        var messages: [LivechatMessage]
        var hasMore = false
    }

    static func page(_ messages: LivechatMessage...) -> Page {
        Page(messages: messages)
    }
}
