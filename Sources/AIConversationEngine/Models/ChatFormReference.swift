//
//  ChatFormReference.swift
//  AIConversationEngine
//

import Foundation

/// Lightweight form row from `GET /api/v1/chat/config` → `forms[]`.
///
/// [API ref](https://docs.askdiverge.ai/api#model/chatformreference)
package struct ChatFormReference: Decodable, Sendable, Equatable {

    package let formId: String
    /// Operator-facing form name. `nil` when the form is unnamed.
    package let name: String?
    package let trigger: Trigger

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.trigger = try container.decode(Trigger.self, forKey: .trigger)
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, trigger
    }

    /// The moment in the conversation the form belongs to, chosen by the operator who sets up
    /// the form. The backend lists the form in `/config` under that trigger, and the client shows
    /// it at that moment: when the session starts (`session_start`), while the visitor waits for
    /// a live agent (`livechat_waiting`), or when the assistant asks for it (`llm`). A case is
    /// added when the backend introduces a new moment and the SDK ships UI for it.
    package enum Trigger: String, ExtendableEnum, Sendable {
        case sessionStart = "session_start"
        case livechatWaiting = "livechat_waiting"
        case llm
        case unknown
    }
}
