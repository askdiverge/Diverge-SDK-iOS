//
//  AttachmentURL.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Shared decode rules for attachment (`image` / `file`) URLs and their signed-URL expiry.
///
/// Attachment URLs are minted by the API and normally absolute, but when the server cannot
/// resolve its own public host it falls back to a bare path (`/api/v1/chat/…/attachments/…`).
/// `URL(string:)` accepts that as a host-less relative URL, which neither `ImageLoader` nor
/// `openURL` can do anything with — so a host-less URL is resolved against the API base the
/// decoder was configured with, and rejected when no base is available.
package enum AttachmentURL {

    /// `JSONDecoder.userInfo` slot carrying the API base URL that relative attachment paths
    /// resolve against. Set by `ChatService`; absent in ad-hoc decoders (tests).
    package static let baseURLKey = CodingUserInfoKey(rawValue: "AIConversationEngine.apiBaseURL")!

    /// Resolves a wire URL string to an absolute URL, or throws `DecodingError.dataCorrupted`
    /// when it is malformed or has no host after resolution.
    package static func resolve(
        _ raw: String,
        in decoder: any Decoder,
        forKey key: some CodingKey
    ) throws -> URL {
        guard let url = Self.resolve(raw, relativeTo: decoder.userInfo[Self.baseURLKey] as? URL) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath + [key],
                debugDescription: "Attachment URL '\(raw)' is malformed or has no host."
            ))
        }
        return url
    }

    /// Resolves `raw` against `base` when it carries no host. Returns nil when the result still
    /// has no host (nothing to resolve against) or the string is not a URL at all.
    ///
    /// `data:` URLs are already absolute and host-less by design — the API re-serves visitor
    /// uploads that way — so they pass without a base.
    package static func resolve(_ raw: String, relativeTo base: URL?) -> URL? {
        if Self.isDataURL(raw), let url = URL(string: raw) {
            return url
        }
        guard let url = URL(string: raw, relativeTo: base)?.absoluteURL, url.host() != nil else {
            return nil
        }
        return url
    }

    /// Case-insensitive `data:` scheme check on the first five bytes only — a data URL can be
    /// megabytes long, and lowercasing the whole string copies all of it on every decode.
    static func isDataURL(_ raw: String) -> Bool {
        let scheme = "data:".utf8
        let head = raw.utf8.prefix(scheme.count)
        return head.count == scheme.count
            && zip(head, scheme).allSatisfy { byte, expected in
                byte == expected || (byte >= 0x41 && byte <= 0x5A && byte | 0x20 == expected)
            }
    }

    /// Parses the wire's `url_expires_at` (ISO 8601, with or without fractional seconds).
    /// Nil when absent or unparseable — callers treat that as "does not expire".
    package static func expiry(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        // Explicit styles on purpose: chaining `.time(includingFractionalSeconds:)` onto `.iso8601`
        // switches the style to opt-in fields and drops the date, so it never matches a full
        // timestamp. The fractional style is tried first; iOS rejects fractional input on the
        // plain style even though macOS accepts it.
        return (try? Date(iso, strategy: Self.fractionalISO8601))
            ?? (try? Date(iso, strategy: Self.plainISO8601))
    }

    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainISO8601 = Date.ISO8601FormatStyle()

    /// True when `url_expires_at` is present, parseable, and already in the past.
    package static func isExpired(_ iso: String?, at now: Date = .now) -> Bool {
        guard let expiry = Self.expiry(iso) else { return false }
        return expiry <= now
    }
}
