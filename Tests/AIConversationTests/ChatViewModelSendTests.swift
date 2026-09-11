//
//  ChatViewModelSendTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — send paths")
@MainActor
struct ChatViewModelSendTests {

    @Test("composer send restores the draft on busy(.streaming)")
    func composerRestoresDraftOnBusy() async throws {
        let provider = StubChatProviding(sendFailure: .busy(.streaming))
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "half typed"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "half typed")
        #expect(viewModel.notice?.message == L10n.noticeBusy.string)
        #expect(provider.lastSent == "half typed")
        #expect(provider.lastAttachments == [])
    }

    @Test("composer send restores the popped text on retry")
    func composerRestoresDraftOnRetry() async throws {
        let provider = StubChatProviding(sendFailure: .retry(popped: "echoed", body: "nope"))
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "echoed"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "echoed")
        #expect(viewModel.notice?.message == "nope")
    }

    @Test("attachment-only send is allowed and restores attachments on busy")
    func attachmentOnlySendRestoresOnBusy() async throws {
        let provider = StubChatProviding(sendFailure: .busy(.streaming))
        let viewModel = self.makeViewModel(provider: provider)
        let pending = PendingAttachment(
            thumbnail: Image(systemName: "photo"),
            attachment: OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "a.jpg"),
            displayName: "a.jpg"
        )
        viewModel.pendingAttachments = [pending]
        viewModel.currentMessage = ""

        try await viewModel.send()

        #expect(viewModel.currentMessage.isEmpty)
        #expect(viewModel.pendingAttachments == [pending])
        #expect(provider.lastSent == "")
        #expect(provider.lastAttachments == [pending.attachment])
        #expect(viewModel.notice?.message == L10n.noticeBusy.string)
    }

    @Test("attachment send restores attachments on retry")
    func attachmentSendRestoresOnRetry() async throws {
        let provider = StubChatProviding(sendFailure: .retry(popped: "caption", body: nil))
        let viewModel = self.makeViewModel(provider: provider)
        let pending = PendingAttachment(
            thumbnail: Image(systemName: "photo"),
            attachment: OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg"),
            displayName: "photo"
        )
        viewModel.pendingAttachments = [pending]
        viewModel.currentMessage = "caption"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "caption")
        #expect(viewModel.pendingAttachments == [pending])
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
    }

    @Test("empty send with no attachments is a no-op")
    func emptySendIsNoOp() async throws {
        let provider = StubChatProviding()
        let viewModel = self.makeViewModel(provider: provider)

        try await viewModel.send()

        #expect(provider.lastSent == nil)
        #expect(viewModel.notice == nil)
    }

    @Test("suggestion send keeps the composer draft on busy(.streaming)")
    func suggestionKeepsDraftOnBusy() async throws {
        let provider = StubChatProviding(sendFailure: .busy(.streaming))
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "still drafting"

        try await viewModel.send(prompt: "Show outfit 1")

        #expect(viewModel.currentMessage == "still drafting")
        #expect(viewModel.notice?.message == L10n.noticeBusy.string)
        #expect(provider.lastSent == "Show outfit 1")
    }

    @Test("suggestion send keeps the composer draft on retry")
    func suggestionKeepsDraftOnRetry() async throws {
        let provider = StubChatProviding(sendFailure: .retry(popped: "Show outfit 1", body: nil))
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "still drafting"

        try await viewModel.send(prompt: "Show outfit 1")

        #expect(viewModel.currentMessage == "still drafting")
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
    }

    @Test("empty suggestion prompt is a no-op")
    func emptyPromptIsNoOp() async throws {
        let provider = StubChatProviding()
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "draft"

        try await viewModel.send(prompt: "")

        #expect(viewModel.currentMessage == "draft")
        #expect(provider.lastSent == nil)
        #expect(viewModel.notice == nil)
    }

    @Test("whitespace-only prompt send is a no-op")
    func whitespacePromptIsNoOp() async throws {
        let provider = StubChatProviding()
        let viewModel = self.makeViewModel(provider: provider)
        viewModel.currentMessage = "draft"

        try await viewModel.send(prompt: "  \n\t  ")

        #expect(viewModel.currentMessage == "draft")
        #expect(provider.lastSent == nil)
        #expect(viewModel.notice == nil)
    }

    @Test("suggestion send surfaces session expiry")
    func suggestionSessionExpired() async {
        let provider = StubChatProviding(sendFailure: .sessionExpired)
        let viewModel = self.makeViewModel(provider: provider)

        await #expect(throws: ChatView.SessionEnded.self) {
            try await viewModel.send(prompt: "Show outfit 1")
        }
    }

    private func makeViewModel(provider: StubChatProviding) -> ChatView.ViewModel {
        .forTesting(provider: provider)
    }
}
