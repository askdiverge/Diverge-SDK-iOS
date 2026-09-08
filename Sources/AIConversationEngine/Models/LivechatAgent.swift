//
//  LivechatAgent.swift
//  AIConversationEngine
//

import Foundation

/// Livechat agent identity shown beside agent turns.
/// [API ref](https://docs.dialoge.ai/api#model/livechat-agent-identity)
package struct LivechatAgent: Decodable, Sendable, Equatable {

    package let agentId: String
    package let displayName: String
    package let avatarUrl: URL?

    package init(agentId: String, displayName: String, avatarUrl: URL? = nil) {
        self.agentId = agentId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agentId = try container.decode(String.self, forKey: .agentId)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        if let raw = try container.decodeIfPresent(String.self, forKey: .avatarUrl),
           let url = URL(string: raw) {
            self.avatarUrl = url
        } else {
            self.avatarUrl = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case agentId, displayName, avatarUrl
    }
}
