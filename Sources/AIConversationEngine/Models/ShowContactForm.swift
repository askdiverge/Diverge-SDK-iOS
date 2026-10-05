//
//  ShowContactForm.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to display a contact / lead form. The marker carries every field the
/// form renders.
///
/// Arrives whole, as a `part` event, in history or in `done`.
/// [API ref](https://docs.askdiverge.ai/api#model/showcontactformmarker)
package struct ShowContactForm: Decodable, Sendable, Equatable {

    package let partId: String
    package let fields: [FormField]

    package init(partId: String, fields: [FormField]) {
        self.partId = partId
        self.fields = fields
    }

    /// `part_id` is required and an absent `fields` decodes as empty. A malformed payload
    /// throws, and the part decoder decides how the message degrades.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.fields = try container.decodeIfPresent([FormField].self, forKey: .fields) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case partId, fields
    }
}
