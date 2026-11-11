//
//  ChatViewModelSendTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The composer's send as the view model drives it, over ``StubChatProviding``.
@Suite("ChatView.ViewModel — sending")
@MainActor
struct ChatViewModelSendTests {

    @Test(
        "a send refused while a reply or another operation is in flight keeps its text; a reply says to wait",
        arguments: [ChatProvider.SendFailure.Reason.streaming, .operation]
    )
    func busySendKeepsText(reason: ChatProvider.SendFailure.Reason) async throws {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding(sendFailure: .busy(reason)))
        viewModel.currentMessage = "hi"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "hi")
        #expect(viewModel.notice?.message == (reason == .streaming ? L10n.noticeBusy.string : nil))
    }

    @Test("a notice shown again after being dismissed stays for its full time")
    func noticeShownAgainLastsItsFullTime() async throws {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        let notice = Notice(edge: .top, message: "hi", autoDismiss: .milliseconds(500))

        viewModel.present(notice)
        try await Task.sleep(for: .milliseconds(300))
        viewModel.dismissNotice()
        viewModel.present(notice)
        try await Task.sleep(for: .milliseconds(300))

        #expect(viewModel.notice == notice)
        try await eventually { viewModel.notice == nil }
    }

    @Test("a send the session expired under goes back in the composer")
    func expiredSendKeepsDraft() async {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding(sendFailure: .sessionExpired))
        viewModel.currentMessage = "hi"

        await #expect(throws: ChatView.SessionEnded.self) {
            try await viewModel.send()
        }

        #expect(viewModel.currentMessage == "hi")
    }
}
