//
//  ChatViewModelLivechatCSATTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The livechat rating prompt as the chat screen drives it: status and feedback state from
/// `LivechatSession` snapshots over `MockChatService`, the submit from an injected closure.
@Suite("ChatView.ViewModel — livechat rating")
@MainActor
struct ChatViewModelLivechatCSATTests {

    @Test("a session that ends while the chat is open asks for a rating when feedback is pending")
    func liveCloseAsks() async throws {
        let (viewModel, service, _, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)

        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()

        try await eventually { viewModel.rating.model != nil }
    }

    @Test("a session already closed when the chat opens isn't asked about")
    func restoredCloseDoesNotAsk() async throws {
        let (viewModel, service, _, _) = self.makeSUT()
        service.livechatState = LivechatState(status: .closed, feedback: .pending)

        viewModel.startLivechat(with: try Self.config())
        try await eventually { viewModel.livechatStatus == .closed }

        #expect(viewModel.rating.model == nil)
    }

    @Test("a skipped prompt sends nothing; a later session can ask again")
    func skipThenNewSession() async throws {
        let (viewModel, service, _, sent) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.rating.model != nil }

        viewModel.rating.dismiss()
        #expect(viewModel.rating.model == nil)

        service.livechatState = LivechatState(status: .active)
        await viewModel.livechat.refresh()
        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.rating.model != nil }
        #expect(sent.values.isEmpty)
    }

    @Test("a rating is sent with its trimmed comment and closes the prompt")
    func submitSends() async throws {
        let (viewModel, service, _, sent) = self.makeSUT()
        try await self.closeLive(viewModel, on: service)

        await viewModel.rating.submit(score: 2, feedback: "  Too slow ")

        #expect(sent.values == [LivechatFeedbackRequest(rating: 2, feedback: "Too slow")])
        #expect(viewModel.rating.model == nil)
    }

    @Test("a refused rating stays for another try, and closes once the session shows it stored")
    func refusedRatingRereadsState() async throws {
        let (viewModel, service, _, _) = self.makeSUT(submit: { _ in
            throw ChatServiceError.transport(.http(.unhandled(status: 500, body: Data())))
        })
        try await self.closeLive(viewModel, on: service)

        await viewModel.rating.submit(score: 5, feedback: nil)
        let model = try #require(viewModel.rating.model)
        #expect(model.phase == .failed(score: 5, feedback: nil, message: L10n.noticeSendFailed.string))

        service.livechatState = LivechatState(status: .closed, feedback: .submitted)
        await viewModel.rating.submit(score: 5, feedback: nil)
        try await eventually { viewModel.rating.model == nil }
    }

    @Test("a 409 means the session holds a rating already, so the prompt closes without an error")
    func conflictedRatingCloses() async throws {
        let (viewModel, service, _, _) = self.makeSUT(submit: { _ in throw ChatServiceError.conflict })
        try await self.closeLive(viewModel, on: service)

        await viewModel.rating.submit(score: 4, feedback: nil)

        #expect(viewModel.rating.model == nil)
    }

    @Test("a rating response that arrives after a reset can't end the new conversation")
    func lateExpiryAfterReset() async throws {
        let entered = AsyncGate()
        let release = AsyncGate()
        let (viewModel, service, provider, _) = self.makeSUT(submit: { _ in
            await entered.open()
            await release.wait()
            throw ChatServiceError.sessionExpired
        })
        try await self.closeLive(viewModel, on: service)

        let submit = Task { await viewModel.rating.submit(score: 4, feedback: nil) }
        await entered.wait()
        await viewModel.reset()
        try await eventually { viewModel.livechatStatus == .inactive }
        await release.open()
        await submit.value

        #expect(provider.expireCount == 0)
        #expect(!viewModel.livechatSessionEnded)
    }

    @Test("a rating that lands after a new session started doesn't stop the next close from asking")
    func lateSuccessKeepsNextPrompt() async throws {
        let entered = AsyncGate()
        let release = AsyncGate()
        let (viewModel, service, _, _) = self.makeSUT(submit: { _ in
            await entered.open()
            await release.wait()
        })
        try await self.closeLive(viewModel, on: service)

        let submit = Task { await viewModel.rating.submit(score: 4, feedback: nil) }
        await entered.wait()
        service.livechatState = LivechatState(status: .active)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .active }
        await release.open()
        await submit.value
        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()

        try await eventually { viewModel.rating.model != nil }
    }

    @Test("a close seen while the chat is off screen asks for a rating once it is back")
    func offScreenCloseWaits() async throws {
        let (viewModel, service, _, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        await viewModel.setVisible(false)
        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .closed }
        #expect(viewModel.rating.model == nil)

        await viewModel.setVisible(true)

        #expect(viewModel.rating.model != nil)
    }

    @Test("a 401 on the rating ends the chat, as the poller's 401 does")
    func expiredRatingEndsChat() async throws {
        let (viewModel, service, provider, _) = self.makeSUT(submit: { _ in throw ChatServiceError.sessionExpired })
        try await self.closeLive(viewModel, on: service)

        await viewModel.rating.submit(score: 4, feedback: nil)

        #expect(provider.expireCount == 1)
        #expect(viewModel.livechatSessionEnded)
        #expect(viewModel.rating.model == nil)
    }

    // MARK: Rating model

    @Test("4 and 5 are sent at once; 1 to 3 ask for a comment")
    func pickSteps() {
        let model = RatingSubmissionModel()

        #expect(!model.pick(5))
        #expect(model.phase == .picking)
        #expect(model.pick(2))
        #expect(model.phase == .feedback(score: 2))
        #expect(model.isFeedbackStep)
    }

    @Test("a failed send keeps the score and comment, and editing returns to the comment step")
    func failureKeepsDraft() {
        let model = RatingSubmissionModel()
        model.pick(2)
        model.beginSubmitting(score: 2, feedback: "slow")

        model.markFailed(message: "failed")
        #expect(model.phase == .failed(score: 2, feedback: "slow", message: "failed"))

        model.editingAfterFailure()
        #expect(model.phase == .feedback(score: 2))
        #expect(model.feedbackText == "slow")
    }
}

private extension ChatViewModelLivechatCSATTests {

    func makeSUT(
        submit: @escaping LivechatRatingController.Submitter = { _ in }
    ) -> (
        viewModel: ChatView.ViewModel,
        service: MockChatService,
        provider: StubChatProviding,
        sent: Recorder<LivechatFeedbackRequest>
    ) {
        let service = MockChatService()
        let provider = StubChatProviding()
        let sent = Recorder<LivechatFeedbackRequest>()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitLivechatFeedback: { request in
                try await submit(request)
                sent.record(request)
            },
            // Ends the poll loop at its first wait, so only the reads a test triggers run.
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        return (viewModel, service, provider, sent)
    }

    func start(_ viewModel: ChatView.ViewModel, in status: LivechatState.Status, on service: MockChatService) async throws {
        service.livechatState = LivechatState(status: status)
        viewModel.startLivechat(with: try Self.config())
        try await eventually { viewModel.livechatStatus == status }
    }

    /// An agent session that ends while the chat is open, with feedback pending.
    func closeLive(_ viewModel: ChatView.ViewModel, on service: MockChatService) async throws {
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.rating.model != nil }
    }

    static func config() throws -> LivechatConfig {
        try LivechatFixtures.decoder.decode(
            LivechatConfig.self,
            from: Data(#"{"enabled":true,"configured":true,"availability_status":"live"}"#.utf8)
        )
    }
}
