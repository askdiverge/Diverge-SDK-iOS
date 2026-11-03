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
        "a send refused while a reply or another operation is in flight keeps its text and says to wait",
        arguments: [ChatProvider.SendFailure.Reason.streaming, .operation]
    )
    func busySendKeepsText(reason: ChatProvider.SendFailure.Reason) async throws {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding(sendFailure: .busy(reason)))
        viewModel.currentMessage = "hi"

        try await viewModel.send()

        #expect(viewModel.currentMessage == "hi")
        #expect(viewModel.notice?.message == L10n.noticeBusy.string)
    }
}
