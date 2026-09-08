//
//  OutgoingAttachment.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A visitor-picked image or file ready to POST — as an `ImageInput` / `FileInput` part on
/// `/messages`, or as an `Attachment` on `/actions` (ticket attachments and form file fields).
///
/// `data` is bare base64 (no `data:` prefix). The message path caps each part at
/// ``maxEncodedLength`` characters (~5 MiB decoded); the action path at the tighter
/// ``maxActionEncodedLength`` (2 MiB decoded).
/// [API ref](https://docs.dialoge.ai/api#model/image-input) ·
/// [Attachment](https://docs.dialoge.ai/api#model/attachment)
package struct OutgoingAttachment: Sendable, Equatable {

    /// Wire discriminator — maps to `ImageInput` vs `FileInput`.
    package enum Kind: Sendable, Equatable {
        case image
        case file
    }

    /// Base64 character cap matching the TypeSpec `@maxLength(6990508)` on `data`.
    package static let maxEncodedLength = 6_990_508

    /// Decoded-size cap on an `/actions` `Attachment` (2 MiB) — the TypeSpec default for
    /// `show_support_ticket.max_attachment_size_bytes` and the cap on custom-form files.
    package static let maxActionDecodedBytes = 2_097_152

    /// Base64 character cap matching the TypeSpec `@maxLength(2796203)` on `Attachment.data_base64`.
    package static let maxActionEncodedLength = 2_796_203

    /// Wire filename used when a form attachment was built without one — the `Attachment`
    /// model requires `filename`, unlike chat images which deliberately omit it.
    package static let fallbackFilename = "attachment.jpg"

    package let kind: Kind
    /// Bare base64 payload — no `data:` prefix.
    package let data: String
    package let mime: String
    package let filename: String?

    package init(kind: Kind, data: String, mime: String, filename: String? = nil) {
        self.kind = kind
        self.data = data
        self.mime = mime
        self.filename = filename
    }

    /// Inline `data:` URL used for the optimistic user-pane echo (and history when the API
    /// re-serves the upload that way). Nil when `URL(string:)` rejects the string.
    package var dataURL: URL? {
        URL(string: "data:\(self.mime);base64,\(self.data)")
    }
}

// MARK: - `/actions` Attachment wire shape

/// Encodes as the `Attachment` model (`filename` / `mime_type` / `data_base64`). Wire names are
/// spelled out here because ``SubmitActionRequest`` is posted with a strategy-free encoder so
/// field-keyed dictionaries keep their keys verbatim.
extension OutgoingAttachment: Encodable {

    private enum ActionCodingKeys: String, CodingKey {
        case filename
        case mimeType = "mime_type"
        case dataBase64 = "data_base64"
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ActionCodingKeys.self)
        try container.encode(self.filename ?? Self.fallbackFilename, forKey: .filename)
        try container.encode(self.mime, forKey: .mimeType)
        try container.encode(self.data, forKey: .dataBase64)
    }
}
