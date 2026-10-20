//
//  Message.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// A single message in a conversation.
/// [API ref](https://docs.askdiverge.ai/api#model/message)
package struct Message: Decodable, Sendable, Equatable {

    package let messageId: String
    package let role: Role
    /// Livechat agent identity for `role: agent` messages. Absent for other roles.
    package let agent: LivechatAgent?
    package let parts: [Part]
    /// ISO 8601 date-time with fractional seconds.
    package let createdAt: String
}

extension Message {

    /// [API ref](https://docs.askdiverge.ai/api#model/messagerole)
    package enum Role: String, ExtendableEnum, Sendable {
        case user, assistant, agent, system, unknown
    }
}
