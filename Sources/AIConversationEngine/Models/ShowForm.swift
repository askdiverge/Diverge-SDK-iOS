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
    package let name: String
    /// Copy shown to the visitor after the form is submitted. `nil` when the form sets none.
    package let confirmationText: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    /// Dashboard `{{form:…}}` / `{{contact_form:…}}` markers arrive as a thin
    /// `{ type, form_id, part_id }` payload (fields hydrate via `GET …/forms/{id}`), so only
    /// `part_id` and `form_id` are required. Missing `name` falls back to `form_id`. A malformed
    /// payload throws, and the part decoder decides how the message degrades.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.formId = try container.decode(String.self, forKey: .formId)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (decodedName?.isEmpty == false) ? decodedName! : self.formId
        self.confirmationText = try container.decodeIfPresent(String.self, forKey: .confirmationText)
        self.fields = try container.decodeIfPresent([FormField].self, forKey: .fields) ?? []
        self.minFilledFields = try container.decodeIfPresent(Int.self, forKey: .minFilledFields) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case partId, formId, name, confirmationText, fields, minFilledFields
    }
}
