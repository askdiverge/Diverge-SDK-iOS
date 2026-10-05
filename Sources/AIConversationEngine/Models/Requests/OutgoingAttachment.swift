//
//  OutgoingAttachment.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import UniformTypeIdentifiers

/// A visitor-picked file ready to POST as an `Attachment` on `/actions` (ticket attachments and
/// form file fields). Encodes as `filename` / `mime_type` / `data_base64`.
/// [API ref](https://docs.askdiverge.ai/api#model/attachment)
package struct OutgoingAttachment: Encodable, Sendable, Equatable {

    /// Decoded-size cap on an `/actions` `Attachment` (2 MiB) — the TypeSpec default for
    /// `show_support_ticket.max_attachment_size_bytes` and the cap on custom-form files.
    package static let maxActionDecodedBytes = 2_097_152

    /// Base64 character cap matching the TypeSpec `@maxLength(2796203)` on `Attachment.data_base64`.
    package static let maxActionEncodedLength = 2_796_203

    /// Bare base64 payload — no `data:` prefix.
    package let dataBase64: String
    /// MIME type of the file, for example `image/jpeg` or `application/pdf`.
    package let mimeType: String
    /// The wire filename: the picked file's name, or `attachment` with the extension
    /// `mimeType` implies.
    package let filename: String

    /// `nil` when `dataBase64` is longer than ``maxActionEncodedLength``, so an oversized file
    /// is rejected before it is uploaded.
    package init?(data: String, mime: String, filename: String?) {
        guard data.utf8.count <= Self.maxActionEncodedLength else { return nil }
        self.dataBase64 = data
        self.mimeType = mime
        self.filename = filename
            ?? UTType(mimeType: mime)?.preferredFilenameExtension.map { "attachment.\($0)" }
            ?? "attachment"
    }
}
