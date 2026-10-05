//
//  ChatFormDefinition.swift
//  AIConversationEngine
//

import Foundation

/// Full form definition from `GET /api/v1/chat/forms/{form_id}`.
///
/// Used to hydrate thin `show_form` markers that only carry `form_id` on the wire.
/// [API ref](https://docs.askdiverge.ai/api#model/chatformdefinition)
package struct ChatFormDefinition: Decodable, Sendable, Equatable {

    package let formId: String
    /// Operator-facing form name. `nil` when the form is unnamed.
    package let name: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.fields = try container.decodeIfPresent([FormField].self, forKey: .fields) ?? []
        self.minFilledFields = try container.decodeIfPresent(Int.self, forKey: .minFilledFields) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, fields, minFilledFields
    }
}
