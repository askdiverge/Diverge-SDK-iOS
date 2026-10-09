//
//  LivechatMessage.swift
//  AIConversationEngine
//

import Foundation

/// A message in the livechat session log: the ``Message`` fields plus its position in the log.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatmessage)
package struct LivechatMessage: Decodable, Sendable, Equatable {

    package let messageId: String
    package let role: Message.Role
    /// The agent's identity on `role: agent` messages.
    package let agent: LivechatAgent?
    package let parts: [Part]
    /// ISO 8601 date-time.
    package let createdAt: String
    /// Increases by one per message in the session; the poll cursor.
    package let sequenceNumber: Int64
}

/// A page of livechat messages from `GET /livechat/messages`, oldest first.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatmessagepage)
package struct LivechatMessagePage: Decodable, Sendable, Equatable {
    package let messages: [LivechatMessage]
    package let hasMore: Bool
}

/// The `POST /livechat/messages` response. Only the nested `message` is read; the API repeats
/// its fields at the top level for older clients.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatvisitormessageresponse)
struct LivechatVisitorMessageResponse: Decodable, Sendable {
    let message: LivechatMessage
}
