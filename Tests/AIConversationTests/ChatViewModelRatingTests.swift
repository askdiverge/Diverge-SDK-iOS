//
//  ChatViewModelRatingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — conversation rating")
@MainActor
struct ChatViewModelRatingTests {

    @Test("shouldOfferRating is false with no user turn")
    func noUserTurnSkipsOffer() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [Identified(model: [.text(AttributedString("Welcome"))])],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldOfferRating == false)
    }

    @Test("shouldOfferRating is true once a user turn exists and rating is enabled")
    func userTurnOffersRating() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldOfferRating == true)
        #expect(viewModel.showsCloseButton == true)
    }

    @Test("shouldOfferRating is false when the host disabled rating")
    func disabledRatingNeverOffers() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            conversationRatingMode: .disabled
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldOfferRating == false)
        #expect(viewModel.showsCloseButton == true)
    }

    @Test("shouldOfferRating is false when onClose is nil — no close button either")
    func noOnCloseHidesButton() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider, onClose: nil)
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.showsCloseButton == false)
        #expect(viewModel.shouldOfferRating == false)
    }

    @Test("a successful submit marks the session rated so a later close does not re-ask")
    func submitSuccessMarksRated() async {
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        viewModel.conversationRating.begin()
        let succeeded = await viewModel.conversationRating.submit(score: 5, feedback: nil)

        #expect(succeeded == true)
        #expect(session.hasRated == true)
        #expect(viewModel.shouldOfferRating == false)
        #expect(viewModel.conversationRating.model == nil)
    }

    @Test("closing with nothing to rate tells the host at once")
    func closeWithoutRating() async {
        let closes = Recorder<Int>()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider, onClose: { closes.record(1) })

        viewModel.close()

        #expect(closes.count == 1)
        #expect(viewModel.conversationRating.model == nil)
    }

    @Test("a rating due on close opens the prompt, and the host hears the close only once it has gone")
    func closeAfterRating() async {
        let closes = Recorder<Int>()
        let sent = Recorder<RateConversationRequest>()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            rateConversation: { sent.record($0) }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        viewModel.close()
        #expect(viewModel.conversationRating.model != nil)
        #expect(closes.count == 0)

        await viewModel.submitRating(score: 4, feedback: nil)
        #expect(sent.values == [RateConversationRequest(rating: 4, feedback: nil)])
        #expect(closes.count == 0)

        viewModel.ratingDidDismiss()
        viewModel.ratingDidDismiss()
        #expect(closes.count == 1)
    }

    @Test("a skipped rating sends nothing and closes once the prompt has gone")
    func skipThenClose() async {
        let closes = Recorder<Int>()
        let sent = Recorder<RateConversationRequest>()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            rateConversation: { sent.record($0) }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.close()

        viewModel.skipRating()
        #expect(closes.count == 0)
        viewModel.ratingDidDismiss()

        #expect(closes.count == 1)
        #expect(sent.values.isEmpty)
    }

    @Test("a refused rating stays on the prompt and doesn't close the chat")
    func refusedRatingStays() async {
        let closes = Recorder<Int>()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            rateConversation: { _ in throw ChatServiceError.transport(.http(.unhandled(status: 500, body: Data()))) }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.close()

        await viewModel.submitRating(score: 2, feedback: "slow")
        viewModel.ratingDidDismiss()

        #expect(viewModel.conversationRating.model != nil)
        #expect(closes.count == 0)
    }

    @Test("a 401 on the rating ends the chat, clears the rated flag and doesn't close")
    func expiredRatingEndsChat() async {
        let closes = Recorder<Int>()
        let session = RatingSession()
        session.markRated()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            ratingSession: session,
            rateConversation: { _ in throw ChatServiceError.sessionExpired }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.conversationRating.begin()

        await viewModel.submitRating(score: 5, feedback: nil)
        viewModel.ratingDidDismiss()

        #expect(provider.expireCount == 1)
        #expect(viewModel.livechatSessionEnded)
        #expect(!session.hasRated)
        #expect(closes.count == 0)
    }

    @Test("rating waits while livechat is open or has feedback pending, and resumes once it hasn't")
    func livechatGatesConversationRating() async throws {
        let service = MockChatService()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        #expect(viewModel.shouldOfferRating == true)

        service.livechatState = LivechatState(status: .waiting)
        viewModel.startLivechat(with: try LivechatFixtures.decoder.decode(
            LivechatConfig.self,
            from: Data(#"{"enabled":true,"configured":true,"availability_status":"live"}"#.utf8)
        ))
        try await eventually { viewModel.livechatStatus == .waiting }
        #expect(viewModel.shouldOfferRating == false)

        service.livechatState = LivechatState(status: .closed, feedback: .pending)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .closed }
        #expect(viewModel.shouldOfferRating == false)

        service.livechatState = LivechatState(status: .closed, feedback: .submitted)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.shouldOfferRating }
    }

    private static func snapshotWithUserTurn() -> ConversationSnapshot {
        ConversationSnapshot(
            user: [Identified(model: [AttributedString("hello")])],
            incoming: [Identified(model: [.text(AttributedString("Hi"))])],
            isUserInitiatedConversation: true,
            streamingTurnID: nil
        )
    }

    private static func waitForSnapshot(_ viewModel: ChatView.ViewModel) async {
        for _ in 0..<20 {
            if viewModel.snapshot != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
