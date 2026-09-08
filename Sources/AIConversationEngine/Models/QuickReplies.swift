//
//  QuickReplies.swift
//  AIConversation
//

import Foundation

/// In-conversation quick-reply chips emitted as a structured assistant part.
/// [API ref](https://docs.dialoge.ai/api#model/quick-replies-content)
package struct QuickReplies: Decodable, Sendable, Equatable {

    package let partId: String
    package let replies: [String]

    package init(partId: String, replies: [String]) {
        self.partId = partId
        self.replies = replies
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.replies =
            try container.decodeIfPresent(LossyArray<String>.self, forKey: .replies)?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case partId, replies
    }
}
