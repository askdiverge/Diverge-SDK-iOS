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
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// [API ref](https://docs.dialoge.ai/api#model/show-support-ticket-marker)
package struct ShowSupportTicket: Decodable, Sendable, Equatable {

    /// Contract default when `max_attachment_size_bytes` is absent (2 MiB) — matches the
    /// backend factory and the TypeSpec `Attachment` decoded-size cap.
    package static let defaultMaxAttachmentSizeBytes = OutgoingAttachment.maxActionDecodedBytes

    package let partId: String
    package let fields: [FormField]
    package let attachmentsAccepted: Bool
    package let maxAttachmentSizeBytes: Int

    package init(
        partId: String,
        fields: [FormField],
        attachmentsAccepted: Bool = true,
        maxAttachmentSizeBytes: Int = Self.defaultMaxAttachmentSizeBytes
    ) {
        self.partId = partId
        self.fields = fields
        self.attachmentsAccepted = attachmentsAccepted
        self.maxAttachmentSizeBytes = maxAttachmentSizeBytes
    }

    /// Soft on optional fields — a marker whose attachment flags are missing still renders.
    /// `part_id` is required; without it the part falls back to `.unknown` upstream.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        self.fields = (try? container.decodeIfPresent(LossyArray<FormField>.self, forKey: .fields))?.elements ?? []
        self.attachmentsAccepted = (try? container.decodeIfPresent(Bool.self, forKey: .attachmentsAccepted)) ?? true
        self.maxAttachmentSizeBytes = (try? container.decodeIfPresent(Int.self, forKey: .maxAttachmentSizeBytes))
            ?? Self.defaultMaxAttachmentSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case partId, fields, attachmentsAccepted, maxAttachmentSizeBytes
    }
}
