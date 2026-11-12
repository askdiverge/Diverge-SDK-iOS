//
//  MessageFileViewTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("MessageFileView — accessibility contract")
@MainActor
struct MessageFileViewTests {

    @Test("an https file opens, shows its size, and VoiceOver reads the name then the size")
    func sizeWhileOpenable() throws {
        let file = try LivechatFixtures.file(sizeBytes: 1200)
        let size = Int64(1200).formatted(.byteCount(style: .file))

        #expect(MessageFileView.canOpen(file, linkExpired: false))
        #expect(MessageFileView.detail(for: file, linkExpired: false) == size)
        #expect(MessageFileView.accessibilityLabel(for: file, linkExpired: false) == "order.pdf. \(size)")
    }

    @Test("a signed link past its expiry still opens; the tap fetches a fresh one")
    func expiredLinkStillOpens() throws {
        let file = try LivechatFixtures.file(sizeBytes: 1200, expiresAt: "2000-01-01T00:00:00Z")

        #expect(file.isExpired())
        #expect(MessageFileView.canOpen(file, linkExpired: false))
        #expect(MessageFileView.detail(for: file, linkExpired: false) == Int64(1200).formatted(.byteCount(style: .file)))
    }

    @Test("an expired link the log couldn't re-sign can't be opened and says it is unavailable")
    func unresignedLinkIsUnavailable() throws {
        let file = try LivechatFixtures.file(sizeBytes: 1200, expiresAt: "2000-01-01T00:00:00Z")

        #expect(!MessageFileView.canOpen(file, linkExpired: true))
        #expect(MessageFileView.detail(for: file, linkExpired: true) == L10n.mediaUnavailable.string)
        #expect(MessageFileView.accessibilityLabel(for: file, linkExpired: true) == "order.pdf. \(L10n.mediaUnavailable.string)")
    }

    @Test("a data: file can't be opened and says it is unavailable, on screen and to VoiceOver")
    func dataLinkIsUnavailable() throws {
        let file = try LivechatFixtures.file(url: "data:application/pdf;base64,AAAA", sizeBytes: 3)

        #expect(!MessageFileView.canOpen(file, linkExpired: false))
        #expect(MessageFileView.detail(for: file, linkExpired: false) == L10n.mediaUnavailable.string)
        #expect(MessageFileView.accessibilityLabel(for: file, linkExpired: false) == "order.pdf. \(L10n.mediaUnavailable.string)")
    }

    @Test("a file without a size shows no detail, and VoiceOver reads the name alone")
    func nameWithoutSize() throws {
        let file = try LivechatFixtures.file()

        #expect(MessageFileView.detail(for: file, linkExpired: false) == nil)
        #expect(MessageFileView.accessibilityLabel(for: file, linkExpired: false) == "order.pdf")
    }
}
