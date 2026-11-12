//
//  ChatFormValuesPatchRequest.swift
//  AIConversationEngine
//

import Foundation

/// Request body for `PATCH /api/v1/chat/forms/{form_id}/values`. Field keys go out verbatim,
/// like ``SubmitActionRequest`` field maps.
/// [API ref](https://docs.askdiverge.ai/api#model/chatformvaluespatchrequest)
package struct ChatFormValuesPatchRequest: Encodable, Sendable, Equatable {

    /// Submitted values keyed by form field key. Only these keys change; the server skips an empty
    /// value and keeps what it stored.
    package let values: [String: String]

    package init(values: [String: String]) {
        self.values = values
    }
}
