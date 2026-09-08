//
//  ChatFormValuesPatchRequest.swift
//  AIConversationEngine
//

import Foundation

/// Request body for `PATCH /api/v1/chat/forms/{form_id}/values`.
///
/// Encoded with a **strategy-free** encoder so dictionary field keys stay verbatim
/// (same reason as ``SubmitActionRequest``).
/// [API ref](https://docs.dialoge.ai/api#model/chat-form-values-patch-request)
package struct ChatFormValuesPatchRequest: Encodable, Sendable, Equatable {

    /// Submitted values keyed by form field key. Empty strings should be omitted by the caller.
    package let values: [String: String]

    package init(values: [String: String]) {
        self.values = values
    }
}
