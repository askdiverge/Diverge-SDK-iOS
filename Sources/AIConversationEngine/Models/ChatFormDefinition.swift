//
//  ChatFormDefinition.swift
//  AIConversationEngine
//

import Foundation

/// Full form definition from `GET /api/v1/chat/forms/{form_id}`.
///
/// Used to hydrate a `show_form` marker whose `fields` arrive empty.
/// [API ref](https://docs.askdiverge.ai/api#model/chatformdefinition)
package struct ChatFormDefinition: Decodable, Sendable, Equatable {

    package let formId: String
    /// Operator-facing form name. `nil` when the form is unnamed.
    package let name: String?
    /// Copy shown to the visitor after the form is submitted. `nil` when the form sets none.
    package let confirmationText: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    /// The keys the contract requires must be present; `name` may be `null`. A missing key throws.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formId = try container.decode(String.self, forKey: .formId)
        self.name = try container.decode(String?.self, forKey: .name)
        self.confirmationText = try container.decodeIfPresent(String.self, forKey: .confirmationText)
        self.fields = try container.decode([FormField].self, forKey: .fields)
        self.minFilledFields = try container.decode(Int.self, forKey: .minFilledFields)
    }

    private enum CodingKeys: String, CodingKey {
        case formId, name, confirmationText, fields, minFilledFields
    }
}
