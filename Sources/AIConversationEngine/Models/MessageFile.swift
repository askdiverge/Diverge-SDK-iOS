//
//  MessageFile.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A file attachment part on a persisted message, in history or in `done`.
/// [API ref](https://docs.askdiverge.ai/api#model/filecontent)
package struct MessageFile: Decodable, Sendable, Equatable {

    package let filename: String
    package let url: URL
    package let attachmentId: String?
    package let mimeType: String?
    package let sizeBytes: Int?
    /// ISO 8601 date-time — optional expiry for signed download URLs. See `isExpired(at:)`.
    package let urlExpiresAt: String?

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filename = try container.decode(String.self, forKey: .filename)
        self.url = try AttachmentURL.resolve(
            container.decode(String.self, forKey: .url),
            in: decoder,
            forKey: CodingKeys.url
        )
        self.attachmentId = try container.decodeIfPresent(String.self, forKey: .attachmentId)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.sizeBytes = try container.decodeIfPresent(Int.self, forKey: .sizeBytes)
        self.urlExpiresAt = try container.decodeIfPresent(String.self, forKey: .urlExpiresAt)
    }

    private enum CodingKeys: String, CodingKey {
        case filename, url, attachmentId, mimeType, sizeBytes, urlExpiresAt
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
