//
//  ShowForm.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to display a client-managed custom chat form. Field definitions,
/// confirmation copy and the minimum-filled count travel inline. `submit_actions` /
/// `submit_rules` are server-side routing — the client only echoes `part_id` on submit.
///
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// [API ref](https://docs.askdiverge.ai/api#model/showformmarker)
package struct ShowForm: Decodable, Sendable, Equatable {

    package let partId: String
    package let formId: String
    package let name: String
    package let confirmationText: String?
    package let fields: [FormField]
    package let minFilledFields: Int

    package init(
        partId: String,
        formId: String,
        name: String,
        confirmationText: String? = nil,
        fields: [FormField],
        minFilledFields: Int = 0
    ) {
        self.partId = partId
        self.formId = formId
        self.name = name
        self.confirmationText = confirmationText
        self.fields = fields
        self.minFilledFields = minFilledFields
    }

    /// Soft on optional fields — dashboard `{{form:…}}` / `{{contact_form:…}}` markers arrive
    /// as a thin `{ type, form_id, part_id }` payload (fields hydrate via `GET …/forms/{id}`).
    /// Missing `name` falls back to `form_id`; without `part_id` / `form_id` the part becomes
    /// `.unknown` upstream.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.formId = try container.decode(String.self, forKey: .formId)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (decodedName?.isEmpty == false) ? decodedName! : self.formId
        // Missing, explicit null and malformed all become nil.
        self.confirmationText = try? container.decodeIfPresent(String.self, forKey: .confirmationText)
        self.fields = (try? container.decodeIfPresent(LossyArray<FormField>.self, forKey: .fields))?.elements ?? []
        self.minFilledFields = (try? container.decodeIfPresent(Int.self, forKey: .minFilledFields)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case partId, formId, name, confirmationText, fields, minFilledFields
    }
}
