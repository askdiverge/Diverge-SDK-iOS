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

    @Test(
        "a session ended by a send or a history load clears the rated flag, so the next conversation is asked",
        arguments: [true, false]
    )
    func otherExpiryPathsClearRatedFlag(throughSend: Bool) async {
        let session = RatingSession()
        session.markRated()
        let provider = StubChatProviding(sendFailure: throughSend ? .sessionExpired : nil)
        provider.loadOlderError = throughSend ? nil : ChatServiceError.sessionExpired
        let viewModel = ChatView.ViewModel.forTesting(provider: provider, ratingSession: session)

        if throughSend {
            viewModel.currentMessage = "hi"
            await #expect(throws: ChatView.SessionEnded.self) { try await viewModel.send() }
        } else {
            await #expect(throws: ChatView.SessionEnded.self) { try await viewModel.loadOlder() }
        }

        #expect(!session.hasRated)
    }

    @Test("a rating that lands after its prompt went away doesn't mark the next conversation rated")
    func lateRatingIsDropped() async {
        let entered = AsyncGate()
        let release = AsyncGate()
        let closes = Recorder<Int>()
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            ratingSession: session,
            rateConversation: { _ in
                await entered.open()
                await release.wait()
            }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.conversationRating.begin()

        let submit = Task { await viewModel.submitRating(score: 5, feedback: nil) }
        await entered.wait()
        await viewModel.reset()
        await release.open()
        await submit.value
        viewModel.ratingDidDismiss()

        #expect(!session.hasRated)
        #expect(closes.count == 0)
    }

    @Test("closing while a handover is pending goes straight to the host")
    func closeDuringHandover() async throws {
        let entered = AsyncGate()
        let release = AsyncGate()
        let closes = Recorder<Int>()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            livechat: LivechatSession(service: MockChatService()) { _ in throw CancellationError() },
            contextProvider: {
                await entered.open()
                await release.wait()
                return nil
            }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.startLivechat(with: try Self.livechatConfig())

        let handover = Task { await viewModel.toggleLivechat() }
        await entered.wait()
        viewModel.close()

        #expect(closes.count == 1)
        #expect(viewModel.conversationRating.model == nil)
        await release.open()
        await handover.value
    }

    @Test("a session that starts under the close prompt dismisses it and keeps the chat open")
    func sessionStartDismissesPrompt() async throws {
        let closes = Recorder<Int>()
        let service = MockChatService()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { closes.record(1) },
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)
        viewModel.close()
        #expect(viewModel.conversationRating.model != nil)

        service.livechatState = LivechatState(status: .waiting)
        viewModel.startLivechat(with: try Self.livechatConfig())

        try await eventually { viewModel.conversationRating.model == nil }
        viewModel.ratingDidDismiss()
        #expect(closes.count == 0)
    }

    private static func livechatConfig() throws -> LivechatConfig {
        try LivechatFixtures.decoder.decode(
            LivechatConfig.self,
            from: Data(#"{"enabled":true,"configured":true,"availability_status":"live"}"#.utf8)
        )
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
