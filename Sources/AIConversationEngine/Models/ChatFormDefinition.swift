//
//  ChatFormDefinition.swift
//  AIConversationEngine
//

import Foundation

/// Full form definition from `GET /api/v1/chat/forms/{form_id}`.
///
/// Used to hydrate thin `show_form` markers that only carry `form_id` on the wire.
/// Prompt / submit_actions / submit_rules stay server-side.
/// [API ref](https://docs.askdiverge.ai/api#model/chatformdefinition)
package struct ChatFormDefinition: Decodable, Sendable, Equatable {

    package let formId: String
    package let name: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    package init(
        formId: String,
        name: String? = nil,
        fields: [FormField],
        minFilledFields: Int = 0
    ) {
        self.formId = formId
        self.name = name
        self.fields = fields
        self.minFilledFields = minFilledFields
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.fields =
            (try? container.decodeIfPresent(LossyArray<FormField>.self, forKey: .fields))?.elements
            ?? []
        self.minFilledFields = try container.decodeIfPresent(Int.self, forKey: .minFilledFields) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, fields, minFilledFields
    }
}
