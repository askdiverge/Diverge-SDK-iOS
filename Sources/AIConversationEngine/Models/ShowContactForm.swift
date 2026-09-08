//
//  ShowContactForm.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to display a contact / lead form. Field definitions travel inline —
/// no config cross-reference is required to render.
///
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// [API ref](https://docs.dialoge.ai/api#model/show-contact-form-marker)
package struct ShowContactForm: Decodable, Sendable, Equatable {

    package let partId: String
    package let fields: [FormField]

    package init(partId: String, fields: [FormField]) {
        self.partId = partId
        self.fields = fields
    }

    /// Soft on `fields` — an empty or missing list still produces a marker so the card can
    /// show its title and a disabled submit rather than vanishing. `part_id` is required;
    /// without it the part falls back to `.unknown` upstream.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.fields = (try? container.decodeIfPresent(LossyArray<FormField>.self, forKey: .fields))?.elements ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case partId, fields
    }
}
