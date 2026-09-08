//
//  Message.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// A single message in a conversation.
/// [API ref](https://docs.dialoge.ai/api#model/message)
package struct Message: Decodable, Sendable, Equatable {

    package let messageId: String
    package let role: Role
    /// Livechat agent identity for `role: agent` messages. Absent for other roles.
    package let agent: LivechatAgent?
    package let parts: [Part]
    /// ISO 8601 date-time with fractional seconds.
    package let createdAt: String

    package init(
        messageId: String,
        role: Role,
        agent: LivechatAgent? = nil,
        parts: [Part],
        createdAt: String
    ) {
        self.messageId = messageId
        self.role = role
        self.agent = agent
        self.parts = parts
        self.createdAt = createdAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messageId = try container.decode(String.self, forKey: .messageId)
        self.role = try container.decode(Role.self, forKey: .role)
        self.agent = try container.decodeIfPresent(LivechatAgent.self, forKey: .agent)
        self.parts = try container.decode([Part].self, forKey: .parts)
        self.createdAt = try container.decode(String.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case messageId, role, agent, parts, createdAt
    }
}

extension Message {

    /// [API ref](https://docs.dialoge.ai/api#model/message-role)
    package enum Role: String, ExtendableEnum, Sendable {
        case user, assistant, agent, system, unknown
    }
}
