//
//  ShowForm.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to display a client-managed custom chat form. Field definitions,
/// confirmation copy and the minimum-filled count travel inline. On submit the client sends the
/// visitor's values with this `part_id`, and the backend runs the form's submit actions.
///
/// Arrives whole, as a `part` event, in history or in `done`.
/// [API ref](https://docs.askdiverge.ai/api#model/showformmarker)
package struct ShowForm: Decodable, Sendable, Equatable {

    package let partId: String
    package let formId: String
    /// Operator-facing form name, trimmed. `nil` when the operator left it blank.
    package let name: String?
    /// Copy shown to the visitor after the form is submitted. `nil` when the form sets none.
    package let confirmationText: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    package init(
        partId: String,
        formId: String,
        name: String?,
        confirmationText: String? = nil,
        fields: [FormField] = [],
        minFilledFields: Int = 0
    ) {
        self.partId = partId
        self.formId = formId
        self.name = name
        self.confirmationText = confirmationText
        self.fields = fields
        self.minFilledFields = minFilledFields
    }

    /// The keys the contract requires must be present. An empty `fields` is hydrated from
    /// `GET …/forms/{form_id}`. A missing key or malformed payload throws, and the part decoder
    /// decides how the message degrades.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.formId = try container.decode(String.self, forKey: .formId)
        let name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.isEmpty ? nil : name
        self.confirmationText = try container.decodeIfPresent(String.self, forKey: .confirmationText)
        self.fields = try container.decode([FormField].self, forKey: .fields)
        self.minFilledFields = try container.decode(Int.self, forKey: .minFilledFields)
    }

    private enum CodingKeys: String, CodingKey {
        case partId, formId, name, confirmationText, fields, minFilledFields
    }
}
