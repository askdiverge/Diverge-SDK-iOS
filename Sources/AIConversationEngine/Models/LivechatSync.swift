//
//  LivechatSync.swift
//  AIConversationEngine
//

import Foundation

/// One `GET /livechat/sync` response: the visitor's livechat state and the next page of messages,
/// read from one database snapshot.
/// [API ref](https://docs.askdiverge.ai/api#tag/visitor-livechat/GET/api/v1/chat/livechat/sync)
package struct LivechatSync: Decodable, Sendable, Equatable {
    package let state: LivechatState
    /// Messages after the requested sequence number, oldest first. A message that doesn't decode
    /// is left out, so the state and the rest of the log still arrive.
    package let messages: [LivechatMessage]
    /// Whether more messages follow this page.
    package let hasMore: Bool
    /// The change hint the next request waits on. `nil` when the server can't wait for changes;
    /// the client then polls at a fixed interval.
    package let syncCursor: String?
}

extension LivechatSync {

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decode(LivechatState.self, forKey: .state)
        self.messages = try container.decode(LossyArray<LivechatMessage>.self, forKey: .messages).elements
        self.hasMore = try container.decode(Bool.self, forKey: .hasMore)
        self.syncCursor = try container.decodeIfPresent(String.self, forKey: .syncCursor)
    }

    private enum CodingKeys: String, CodingKey {
        case state, messages, hasMore, syncCursor
    }
}
