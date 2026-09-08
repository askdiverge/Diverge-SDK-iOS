//
//  MessageMediaAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Pins the VoiceOver contract of assistant image and file parts, and the expiry rule that
/// drives their unavailable state. Under the `swift test` CLI String Catalogs are not compiled
/// and every key echoes itself, so copy is asserted by key identity, never by English text.
///
/// `@MainActor` because the helpers under test hang off SwiftUI views, which are main-actor
/// isolated — calling them from the default executor trips the runtime isolation check.
@MainActor
@Suite("MessageImageView / MessageFileView — accessibility contract")
struct MessageMediaAccessibilityTests {

    // MARK: - image label

    @Test("image label is the caption when present")
    func imageLabelCaption() {
        let image = self.image(caption: "My order receipt")
        #expect(MessageImageView.accessibilityLabel(for: image, isAvailable: true) == "My order receipt")
    }

    @Test("image label falls back to the generic image copy when the caption is empty")
    func imageLabelEmptyCaption() {
        let image = self.image(caption: "")
        #expect(
            MessageImageView.accessibilityLabel(for: image, isAvailable: true) == L10n.mediaImageLabel.string
        )
    }

    @Test("image label falls back to the generic image copy when there is no caption")
    func imageLabelNoCaption() {
        let image = self.image(caption: nil)
        #expect(
            MessageImageView.accessibilityLabel(for: image, isAvailable: true) == L10n.mediaImageLabel.string
        )
    }

    @Test("an unavailable image appends the unavailable copy and drops the open hint")
    func imageUnavailable() {
        let image = self.image(caption: "Receipt")
        #expect(
            MessageImageView.accessibilityLabel(for: image, isAvailable: false)
                == "Receipt. \(L10n.mediaUnavailable.string)"
        )
        #expect(MessageImageView.accessibilityHint(isAvailable: false).isEmpty)
        #expect(!MessageImageView.accessibilityHint(isAvailable: true).isEmpty)
    }

    // MARK: - file label

    @Test("file label is the filename alone when no size is known")
    func fileLabelNoSize() {
        let file = MessageFile(filename: "invoice.pdf", url: self.url)
        #expect(MessageFileView.accessibilityLabel(for: file, isAvailable: true) == "invoice.pdf")
        #expect(MessageFileView.detail(for: file, isAvailable: true) == nil)
    }

    @Test("file label speaks the formatted size the row shows")
    func fileLabelWithSize() {
        let file = MessageFile(filename: "invoice.pdf", url: self.url, sizeBytes: 48231)
        let size = Int64(48231).formatted(.byteCount(style: .file))
        #expect(MessageFileView.detail(for: file, isAvailable: true) == size)
        #expect(MessageFileView.accessibilityLabel(for: file, isAvailable: true) == "invoice.pdf. \(size)")
    }

    @Test("an unavailable file replaces the size with the unavailable copy")
    func fileUnavailable() {
        let file = MessageFile(filename: "invoice.pdf", url: self.url, sizeBytes: 48231)
        #expect(MessageFileView.detail(for: file, isAvailable: false) == L10n.mediaUnavailable.string)
        #expect(
            MessageFileView.accessibilityLabel(for: file, isAvailable: false)
                == "invoice.pdf. \(L10n.mediaUnavailable.string)"
        )
    }

    // MARK: - expiry rule

    @Test("no url_expires_at never expires")
    func noExpiry() {
        #expect(!MessageImage(url: self.url).isExpired(at: .distantFuture))
        #expect(!MessageFile(filename: "a.pdf", url: self.url).isExpired(at: .distantFuture))
    }

    @Test("url_expires_at is compared against the supplied clock, fractional seconds or not")
    func expiryClock() {
        let image = MessageImage(url: self.url, urlExpiresAt: "2026-09-05T10:00:00.000Z")
        let file = MessageFile(filename: "a.pdf", url: self.url, urlExpiresAt: "2026-09-05T10:00:00Z")
        let before = Date(timeIntervalSince1970: 1_788_602_399) // 2026-09-05T09:59:59Z
        let after = Date(timeIntervalSince1970: 1_788_602_401) // 2026-09-05T10:00:01Z
        #expect(!image.isExpired(at: before))
        #expect(image.isExpired(at: after))
        #expect(!file.isExpired(at: before))
        #expect(file.isExpired(at: after))
    }

    @Test("urlExpiry parses fractional and whole-second timestamps to the same instant")
    func urlExpiryParses() {
        // Regression: a chained `.iso8601.time(includingFractionalSeconds:)` style silently
        // parsed nothing on device, so the expiry watcher never armed.
        let expected = Date(timeIntervalSince1970: 1_788_602_400)
        #expect(MessageImage(url: self.url, urlExpiresAt: "2026-09-05T10:00:00.792Z").urlExpiry?
            .timeIntervalSince1970.rounded(.down) == expected.timeIntervalSince1970)
        #expect(MessageFile(filename: "a.pdf", url: self.url, urlExpiresAt: "2026-09-05T10:00:00Z").urlExpiry == expected)
        #expect(MessageImage(url: self.url, urlExpiresAt: "2026-09-05T12:00:00+02:00").urlExpiry == expected)
        #expect(MessageImage(url: self.url).urlExpiry == nil)
    }

    @Test("an unparseable url_expires_at is treated as not expiring")
    func unparseableExpiry() {
        let image = MessageImage(url: self.url, urlExpiresAt: "tomorrow-ish")
        #expect(!image.isExpired(at: .distantFuture))
    }

    // MARK: - Tappability

    @Test("only http(s) tiles open — inline data: uploads render but are not tappable")
    func canOpenSchemes() throws {
        #expect(MessageImageView.canOpen(self.url))
        #expect(MessageImageView.canOpen(URL(string: "HTTP://cdn.example.com/a.jpg")!))
        let inline = try #require(OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg").dataURL)
        #expect(!MessageImageView.canOpen(inline))
        #expect(!MessageImageView.canOpen(URL(string: "file:///tmp/a.jpg")!))
        #expect(!MessageImageView.canOpen(URL(string: "ftp://cdn.example.com/a.jpg")!))
    }

    @Test("an expired signed URL is not tappable even though the scheme is http")
    func expiredNotTappable() {
        let expired = MessageImage(url: self.url, urlExpiresAt: "2026-09-05T10:00:00Z")
        let after = Date(timeIntervalSince1970: 1_788_602_401)
        #expect(MessageImageView.canOpen(expired.url))
        #expect(expired.isExpired(at: after))
        // The view composes both: `isTappable = isAvailable && canOpen`, so the hint drops.
        #expect(MessageImageView.accessibilityHint(isAvailable: false).isEmpty)
    }

    private let url = URL(string: "https://cdn.example.com/uploads/receipt.jpg")!

    private func image(caption: String?) -> MessageImage {
        MessageImage(url: self.url, caption: caption)
    }
}
