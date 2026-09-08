//
//  ChatFormReference.swift
//  AIConversationEngine
//

import Foundation

/// Lightweight form row from `GET /api/v1/chat/config` → `forms[]`.
///
/// [API ref](https://docs.dialoge.ai/api#model/chat-form-reference)
package struct ChatFormReference: Decodable, Sendable, Equatable {

    package let formId: String
    package let name: String?
    package let trigger: Trigger

    package init(formId: String, name: String? = nil, trigger: Trigger) {
        self.formId = formId
        self.name = name
        self.trigger = trigger
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, trigger
    }

    /// Where the form is intended to be shown.
    package enum Trigger: String, ExtendableEnum, Sendable {
        case sessionStart = "session_start"
        case livechatWaiting = "livechat_waiting"
        case llm
        case unknown
    }
}
