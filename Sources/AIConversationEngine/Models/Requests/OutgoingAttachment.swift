//
//  OutgoingAttachment.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A visitor-picked image or file ready to POST as an `ImageInput` / `FileInput` part on
/// `/messages`.
///
/// `data` is bare base64 (no `data:` prefix). The message path caps each part at
/// ``maxEncodedLength`` characters (~5 MiB decoded). The wire shape is produced by
/// `SendMessageRequest.Part.make(text:attachments:)`, not by this type.
/// [API ref](https://docs.dialoge.ai/api#model/image-input)
package struct OutgoingAttachment: Sendable, Equatable {

    /// Wire discriminator — maps to `ImageInput` vs `FileInput`.
    package enum Kind: Sendable, Equatable {
        case image
        case file
    }

    /// Base64 character cap matching the TypeSpec `@maxLength(6990508)` on `data`.
    package static let maxEncodedLength = 6_990_508

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
