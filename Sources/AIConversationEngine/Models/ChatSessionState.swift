//
//  ChatSessionState.swift
//  AIConversationEngine
//

import Foundation

/// Materialized visitor session values from `GET /api/v1/chat/session` or a successful
/// `PATCH /api/v1/chat/forms/{form_id}/values`.
///
/// Metadata / verified_metadata are ignored — the waiting form only needs `values`.
/// [API ref](https://docs.dialoge.ai/api#model/chat-session-state)
package struct ChatSessionState: Decodable, Sendable, Equatable {

    package let values: [ChatSessionValue]

    package init(values: [ChatSessionValue] = []) {
        self.values = values
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.values =
            (try? container.decodeIfPresent(LossyArray<ChatSessionValue>.self, forKey: .values))?
            .elements ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case values
    }
}

/// One non-empty session value.
/// [API ref](https://docs.dialoge.ai/api#model/chat-session-value)
package struct ChatSessionValue: Decodable, Sendable, Equatable {

    package let key: String
    package let label: String?
    package let type: String?
    package let value: String
    package let updatedAt: String?

    package init(
        key: String,
        value: String,
        label: String? = nil,
        type: String? = nil,
        updatedAt: String? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.value = value
        self.updatedAt = updatedAt
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.value = try container.decode(String.self, forKey: .value)
        self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, type, value, updatedAt
    }
}
