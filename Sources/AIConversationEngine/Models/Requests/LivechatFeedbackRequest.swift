//
//  LivechatFeedbackRequest.swift
//  AIConversationEngine
//

import Foundation

/// Body for `POST /api/v1/chat/livechat/feedback`: the visitor's rating of the latest closed
/// livechat session, 1 (worst) to 5 (best), with optional free-text feedback.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatfeedbackrequest)
package struct LivechatFeedbackRequest: Encodable, Sendable, Equatable {

    /// Rating from 1 (worst) to 5 (best).
    package let rating: Int

    /// Free-text feedback, trimmed; sent only when something is left.
    package let feedback: String?

    package init(rating: Int, feedback: String?) {
        self.rating = rating
        let trimmed = feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.feedback = trimmed.isEmpty ? nil : trimmed
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rating, forKey: .rating)
        try container.encodeIfPresent(self.feedback, forKey: .feedback)
    }

    private enum CodingKeys: String, CodingKey {
        case rating, feedback
    }
}
