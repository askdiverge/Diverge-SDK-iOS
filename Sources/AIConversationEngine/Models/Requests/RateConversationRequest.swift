//
//  RateConversationRequest.swift
//  AIConversationEngine
//

import Foundation

/// Body for `POST /api/v1/chat/rate`: a 1–5 rating of the active conversation with optional
/// feedback. The spec's inline body has the fields of ``LivechatFeedbackRequest``, so both
/// endpoints share its trimming and encoding.
/// [API ref](https://docs.askdiverge.ai/api#tag/visitor-conversations/POST/api/v1/chat/rate)
package typealias RateConversationRequest = LivechatFeedbackRequest
