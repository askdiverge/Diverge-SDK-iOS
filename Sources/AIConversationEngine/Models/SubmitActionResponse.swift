//
//  SubmitActionResponse.swift
//  AIConversationEngine
//

import Foundation

/// Success body for `POST /api/v1/chat/actions`.
/// [API ref](https://docs.askdiverge.ai/api#tag/visitor-conversations/POST/api/v1/chat/actions)
package struct SubmitActionResponse: Decodable, Sendable, Equatable {

    /// The backend's identifier for the stored submission.
    package let submissionId: String
    /// Copy shown to the visitor after the submission. `nil` when the form sets none; the SDK
    /// then shows its own confirmation copy.
    package let confirmationText: String?

    package init(submissionId: String, confirmationText: String? = nil) {
        self.submissionId = submissionId
        self.confirmationText = confirmationText
    }
}
