//
//  LivechatFeedbackResponse.swift
//  AIConversationEngine
//

import Foundation

/// JSON body of `POST /api/v1/chat/livechat/feedback` (unlike conversation `/rate`, which is empty 200).
///
/// [API ref](https://docs.dialoge.ai/api#operation/Livechat_submitFeedback)
package struct LivechatFeedbackResponse: Decodable, Sendable, Equatable {

    package let livechatSessionId: String?
    package let status: String?
    package let rating: Int?
    package let feedback: String?
    package let submittedAt: String?

    package init(
        livechatSessionId: String? = nil,
        status: String? = nil,
        rating: Int? = nil,
        feedback: String? = nil,
        submittedAt: String? = nil
    ) {
        self.livechatSessionId = livechatSessionId
        self.status = status
        self.rating = rating
        self.feedback = feedback
        self.submittedAt = submittedAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.livechatSessionId = try container.decodeIfPresent(String.self, forKey: .livechatSessionId)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        self.feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
        self.submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case livechatSessionId, status, rating, feedback, submittedAt
    }
}
