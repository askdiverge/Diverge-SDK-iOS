//
//  ShowSupportTicket.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to display a support-ticket form. Field definitions and attachment
/// constraints travel inline.
///
/// Arrives whole, as a `part` event, in history or in `done`.
/// [API ref](https://docs.askdiverge.ai/api#model/showsupportticketmarker)
package struct ShowSupportTicket: Decodable, Sendable, Equatable {

    package let partId: String
    package let fields: [FormField]
    package let attachmentsAccepted: Bool
    package let maxAttachmentSizeBytes: Int

    /// Every key is required. A missing key or malformed payload throws, and the part decoder
    /// decides how the message degrades.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.fields = try container.decode([FormField].self, forKey: .fields)
        self.attachmentsAccepted = try container.decode(Bool.self, forKey: .attachmentsAccepted)
        self.maxAttachmentSizeBytes = try container.decode(Int.self, forKey: .maxAttachmentSizeBytes)
    }

    private enum CodingKeys: String, CodingKey {
        case partId, fields, attachmentsAccepted, maxAttachmentSizeBytes
    }
}
