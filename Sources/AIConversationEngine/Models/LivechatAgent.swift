//
//  LivechatAgent.swift
//  AIConversationEngine
//

import Foundation

/// Livechat agent identity shown beside agent turns.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatagentidentity)
package struct LivechatAgent: Decodable, Sendable, Equatable {

    package let agentId: String
    package let displayName: String
    /// The agent's avatar, resolved like an attachment URL. `nil` when the API sends `null` or a
    /// URL that doesn't resolve to an absolute one; the client then shows its fallback avatar.
    package let avatarUrl: URL?

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.agentId = try container.decode(String.self, forKey: .agentId)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl).flatMap {
            AttachmentURL.resolve($0, relativeTo: decoder.userInfo[AttachmentURL.baseURLKey] as? URL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case agentId, displayName, avatarUrl
    }
}
