//
//  LivechatMessage.swift
//  AIConversationEngine
//

import Foundation

/// A livechat transcript message — `Message` fields plus a session sequence number.
/// [API ref](https://docs.dialoge.ai/api#model/livechat-message)
package struct LivechatMessage: Decodable, Sendable, Equatable {

    package let messageId: String
    package let role: Message.Role
    package let agent: LivechatAgent?
    package let parts: [Part]
    package let createdAt: String
    package let sequenceNumber: Int64

    package init(
        messageId: String,
        role: Message.Role,
        agent: LivechatAgent? = nil,
        parts: [Part],
        createdAt: String,
        sequenceNumber: Int64
    ) {
        self.messageId = messageId
        self.role = role
        self.agent = agent
        self.parts = parts
        self.createdAt = createdAt
        self.sequenceNumber = sequenceNumber
    }

    package init(from decoder: any Decoder) throws {
        // Decode Message fields from the same keyed container, then the livechat-only sequence.
        let message = try Message(from: decoder)
        self.messageId = message.messageId
        self.role = message.role
        self.agent = message.agent
        self.parts = message.parts
        self.createdAt = message.createdAt
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sequenceNumber = try container.decode(Int64.self, forKey: .sequenceNumber)
    }

    private enum CodingKeys: String, CodingKey {
        case sequenceNumber
    }

    package var asMessage: Message {
        Message(
            messageId: self.messageId,
            role: self.role,
            agent: self.agent,
            parts: self.parts,
            createdAt: self.createdAt
        )
    }
}

/// Incremental livechat message page from `GET /livechat/messages`.
/// [API ref](https://docs.dialoge.ai/api#model/livechat-message-page)
package struct LivechatMessagePage: Decodable, Sendable, Equatable {
    package let messages: [LivechatMessage]
    package let hasMore: Bool
}


/// Wire envelope for `POST /livechat/messages` — nested `message` is authoritative.
struct LivechatVisitorMessageEnvelope: Decodable, Sendable, Equatable {
    let message: LivechatMessage
}
