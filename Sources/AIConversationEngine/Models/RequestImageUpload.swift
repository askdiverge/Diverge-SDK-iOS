//
//  RequestImageUpload.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Instructs the client to prompt the visitor to upload an image. Carries accepted MIME types
/// and a size limit inline; the SDK owns all copy (the API supplies none).
///
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// [API ref](https://docs.dialoge.ai/api#model/request-image-upload-marker)
package struct RequestImageUpload: Decodable, Sendable, Equatable {

    /// Contract default when `accepted_types` is absent — matches the backend factory.
    package static let defaultAcceptedTypes = ["image/png", "image/jpeg", "image/webp"]

    /// Contract default when `max_size_bytes` is absent (5 MiB). Matches the decoded size of
    /// ``OutgoingAttachment/maxEncodedLength`` to within a byte (6,990,508 base64 chars → 5,242,881).
    package static let defaultMaxSizeBytes = 5_242_880

    package let partId: String
    package let acceptedTypes: [String]
    package let maxSizeBytes: Int

    package init(
        partId: String,
        acceptedTypes: [String] = Self.defaultAcceptedTypes,
        maxSizeBytes: Int = Self.defaultMaxSizeBytes
    ) {
        self.partId = partId
        self.acceptedTypes = acceptedTypes
        self.maxSizeBytes = maxSizeBytes
    }

    /// Lenient decode — a marker whose optional fields are missing, empty or malformed still
    /// renders the CTA rather than vanishing; the SDK does not act on either field yet, so a
    /// bad value is not worth losing the prompt over. `part_id` is required; without it the
    /// part falls back to `.unknown` upstream.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
        if let types = try? container.decodeIfPresent([String].self, forKey: .acceptedTypes),
           !types.isEmpty {
            self.acceptedTypes = types
        } else {
            self.acceptedTypes = Self.defaultAcceptedTypes
        }
        self.maxSizeBytes = (try? container.decodeIfPresent(Int.self, forKey: .maxSizeBytes))
            ?? Self.defaultMaxSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case partId, acceptedTypes, maxSizeBytes
    }
}
