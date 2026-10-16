//
//  OutgoingAttachment.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import UniformTypeIdentifiers

/// A visitor-picked image or file ready to POST — as an `ImageInput` / `FileInput` part on
/// `/messages`, or as an `Attachment` on `/actions` (ticket attachments and form file fields).
///
/// `dataBase64` is bare base64 (no `data:` prefix). The message path caps each part at
/// ``maxEncodedLength`` characters (~5 MiB decoded); the action path at the tighter
/// ``maxActionEncodedLength`` (2 MiB decoded).
/// [API ref](https://docs.askdiverge.ai/api#model/imageinput) ·
/// [Attachment](https://docs.askdiverge.ai/api#model/attachment)
package struct OutgoingAttachment: Sendable, Equatable {

    /// The message part an attachment posts as, chosen by the picker that produced it: `image`
    /// posts an `ImageInput`, which the assistant reads as a photo; `file` posts a `FileInput`.
    package enum Kind: Sendable, Equatable {
        case image
        case file
    }

    /// Base64 character cap matching the TypeSpec `@maxLength(6990508)` on `ImageInput.data`
    /// and `FileInput.data`.
    package static let maxEncodedLength = 6_990_508

    /// Decoded-size cap on an `/actions` `Attachment` (2 MiB) — the cap on custom-form files.
    package static let maxActionDecodedBytes = 2_097_152

    /// Base64 character cap matching the TypeSpec `@maxLength(2796203)` on `Attachment.data_base64`.
    package static let maxActionEncodedLength = 2_796_203

    /// The message part this attachment posts as.
    package let kind: Kind
    /// Bare base64 payload — no `data:` prefix.
    package let dataBase64: String
    /// MIME type of the file, for example `image/jpeg` or `application/pdf`.
    package let mimeType: String
    /// The wire filename: the picked file's name, or `attachment` with the extension
    /// `mimeType` implies. Always set for a `file`; `nil` for an image picked without a name,
    /// which `ImageInput` allows.
    package let filename: String?

    /// A message attachment. `nil` when `data` or `mime` is empty, or `data` is longer than
    /// ``maxEncodedLength``, so a part the contract rejects is never uploaded. A blank `filename`
    /// counts as none.
    package init?(kind: Kind, data: String, mime: String, filename: String?) {
        guard !data.isEmpty, !mime.isEmpty, data.utf8.count <= Self.maxEncodedLength else { return nil }
        self.kind = kind
        self.dataBase64 = data
        self.mimeType = mime
        self.filename = filename.flatMap { $0.isEmpty ? nil : $0 }
            ?? (kind == .file ? Self.defaultFilename(for: mime) : nil)
    }

    /// An `/actions` attachment. `nil` when `data` or `mime` is empty, or `data` is longer than
    /// ``maxActionEncodedLength``, so a file the `Attachment` contract rejects is never uploaded.
    package init?(data: String, mime: String, filename: String?) {
        guard data.utf8.count <= Self.maxActionEncodedLength else { return nil }
        self.init(kind: .file, data: data, mime: mime, filename: filename)
    }

    /// `attachment` with the extension `mime` implies — the filename of a pick that has none.
    private static func defaultFilename(for mime: String) -> String {
        UTType(mimeType: mime)?.preferredFilenameExtension.map { "attachment.\($0)" } ?? "attachment"
    }
}

// MARK: - `/actions` Attachment wire shape

/// Encodes as the `Attachment` model (`filename` / `mime_type` / `data_base64`), whose
/// `filename` is required.
extension OutgoingAttachment: Encodable {

    private enum CodingKeys: String, CodingKey {
        case filename, mimeType, dataBase64
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.filename ?? Self.defaultFilename(for: self.mimeType), forKey: .filename)
        try container.encode(self.mimeType, forKey: .mimeType)
        try container.encode(self.dataBase64, forKey: .dataBase64)
    }
}
