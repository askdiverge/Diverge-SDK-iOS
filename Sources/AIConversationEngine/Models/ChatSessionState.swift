//
//  ChatSessionState.swift
//  AIConversationEngine
//

import Foundation

/// Materialized visitor session values from `GET /api/v1/chat/session` or a successful
/// `PATCH /api/v1/chat/forms/{form_id}/values`. The waiting form reads `values` only.
/// [API ref](https://docs.askdiverge.ai/api#model/chatsessionstate)
package struct ChatSessionState: Decodable, Sendable, Equatable {

    /// The session's current non-empty values.
    package let values: [ChatSessionValue]

    package init(values: [ChatSessionValue]) {
        self.values = values
    }
}

/// One non-empty session value. The waiting form only reads `key` and `value`; other wire fields
/// are ignored.
/// [API ref](https://docs.askdiverge.ai/api#model/chatsessionvalue)
package struct ChatSessionValue: Decodable, Sendable, Equatable {

    package let key: String
    package let value: String

    package init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
