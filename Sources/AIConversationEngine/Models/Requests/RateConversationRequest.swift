//
//  RateConversationRequest.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Body for `POST /api/v1/chat/rate` — rate the active conversation 1–5 with optional feedback.
///
/// The response is an empty 200; there is no decode model. The default encoder's
/// `convertToSnakeCase` is fine here (no dictionary keys that must stay verbatim).
package struct RateConversationRequest: Encodable, Sendable, Equatable {

    /// Rating from 1 (worst) to 5 (best).
    package let rating: Int

    /// Optional free-text feedback. Omitted on the wire when `nil` or blank after trim.
    package let feedback: String?

    package init(rating: Int, feedback: String? = nil) {
        self.rating = rating
        let trimmed = feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.feedback = trimmed.isEmpty ? nil : trimmed
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rating, forKey: .rating)
        try container.encodeIfPresent(self.feedback, forKey: .feedback)
    }

    private enum CodingKeys: String, CodingKey {
        case rating, feedback
    }
}
