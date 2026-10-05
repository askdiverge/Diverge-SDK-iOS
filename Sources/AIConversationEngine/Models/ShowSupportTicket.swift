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

    /// Contract default when `max_attachment_size_bytes` is absent (2 MiB) — matches the
    /// backend factory and the TypeSpec `Attachment` decoded-size cap.
    package static let defaultMaxAttachmentSizeBytes = OutgoingAttachment.maxActionDecodedBytes

    package let partId: String
    package let fields: [FormField]
    package let attachmentsAccepted: Bool
    package let maxAttachmentSizeBytes: Int

    /// `part_id` is required; absent `fields` and attachment flags take their contract defaults.
    /// A malformed payload throws, and the part decoder decides how the message degrades.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.fields = try container.decodeIfPresent([FormField].self, forKey: .fields) ?? []
        self.attachmentsAccepted = try container.decodeIfPresent(Bool.self, forKey: .attachmentsAccepted) ?? true
        self.maxAttachmentSizeBytes = try container.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeBytes)
            ?? Self.defaultMaxAttachmentSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case partId, fields, attachmentsAccepted, maxAttachmentSizeBytes
    }
}
