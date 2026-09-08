//
//  MessageImage.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// An image part returned on a persisted message (history / `done`). Never streams.
/// [API ref](https://docs.dialoge.ai/api#model/image-content)
package struct MessageImage: Decodable, Sendable, Equatable {

    package let url: URL
    package let attachmentId: String?
    package let mimeType: String?
    package let sizeBytes: Int?
    /// ISO 8601 date-time — optional expiry for signed download URLs. See `isExpired(at:)`.
    package let urlExpiresAt: String?
    /// Decoded leniently, unlike `url`: a bad thumbnail must not cost the visitor the full image,
    /// so it falls back to nil and the view loads `url` instead. A bad `url` fails the whole
    /// part, which `Part.init` then downgrades to `.unknown`.
    package let thumbnailUrl: URL?
    package let caption: String?

    package init(
        url: URL,
        attachmentId: String? = nil,
        mimeType: String? = nil,
        sizeBytes: Int? = nil,
        urlExpiresAt: String? = nil,
        thumbnailUrl: URL? = nil,
        caption: String? = nil
    ) {
        self.url = url
        self.attachmentId = attachmentId
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.urlExpiresAt = urlExpiresAt
        self.thumbnailUrl = thumbnailUrl
        self.caption = caption
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try AttachmentURL.resolve(
            container.decode(String.self, forKey: .url),
            in: decoder,
            forKey: CodingKeys.url
        )
        self.attachmentId = try container.decodeIfPresent(String.self, forKey: .attachmentId)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes)
        self.urlExpiresAt = try container.decodeIfPresent(String.self, forKey: .urlExpiresAt)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl).flatMap {
            AttachmentURL.resolve($0, relativeTo: decoder.userInfo[AttachmentURL.baseURLKey] as? URL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case url, attachmentId, mimeType, sizeBytes, urlExpiresAt, thumbnailUrl, caption
    }

    /// `urlExpiresAt` parsed; nil when absent or unparseable (treated as never expiring).
    package var urlExpiry: Date? {
        AttachmentURL.expiry(self.urlExpiresAt)
    }

    /// True once the signed `url` has passed `urlExpiresAt`. Always false when no expiry is set.
    package func isExpired(at now: Date = .now) -> Bool {
        AttachmentURL.isExpired(self.urlExpiresAt, at: now)
    }
}
