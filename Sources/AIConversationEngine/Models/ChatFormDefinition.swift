//
//  ChatFormDefinition.swift
//  AIConversationEngine
//

import Foundation

/// Full form definition from `GET /api/v1/chat/forms/{form_id}`.
///
/// Prompt / submit_actions / submit_rules are ignored — waiting-room submit is
/// `PATCH …/values`, not `POST /actions`.
/// [API ref](https://docs.dialoge.ai/api#model/chat-form-definition)
package struct ChatFormDefinition: Decodable, Sendable, Equatable {

    package let formId: String
    package let name: String?
    package let trigger: ChatFormReference.Trigger
    package let fields: [FormField]
    package let minFilledFields: Int

    package init(
        formId: String,
        name: String? = nil,
        trigger: ChatFormReference.Trigger,
        fields: [FormField],
        minFilledFields: Int = 0
    ) {
        self.formId = formId
        self.name = name
        self.trigger = trigger
        self.fields = fields
        self.minFilledFields = minFilledFields
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.trigger = try container.decodeIfPresent(ChatFormReference.Trigger.self, forKey: .trigger)
            ?? .unknown
        self.fields =
            (try? container.decodeIfPresent(LossyArray<FormField>.self, forKey: .fields))?.elements
            ?? []
        self.minFilledFields = try container.decodeIfPresent(Int.self, forKey: .minFilledFields) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, trigger, fields, minFilledFields
    }
}
