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
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))]))
        ], streamingTurnID: nil, canLoadOlder: false))
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
        let viewModel = ChatView.ViewModel.forTesting(provider: provider, rating: .disabled)
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
    func submitSuccessMarksRated() async throws {
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        _ = viewModel.beginRating()
        try await viewModel.submitRating(score: 5, feedback: nil)

        #expect(session.hasRated == true)
        #expect(viewModel.shouldOfferRating == false)
        #expect(viewModel.ratingModel == nil)
    }

    @Test("feedback skip submits the score with no written feedback")
    func feedbackSkipSubmitsScore() async throws {
        let captured = RatingRequestBox()
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { captured.value = $0 }
        )
        provider.publish(Self.snapshotWithUserTurn())
        await Self.waitForSnapshot(viewModel)

        let model = viewModel.beginRating()
        #expect(model.pick(2) == true)
        #expect(model.isFeedbackStep == true)
        try await viewModel.submitRating(score: 2, feedback: nil)

        #expect(captured.value?.rating == 2)
        #expect(captured.value?.feedback == nil)
        #expect(session.hasRated == true)
        #expect(viewModel.shouldOfferRating == false)
    }

    @Test("submitRating without beginRating is a no-op")
    func submitWithoutBeginIsNoOp() async throws {
        let calls = RatingCallCount()
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in calls.value += 1 }
        )

        try await viewModel.submitRating(score: 5, feedback: nil)

        #expect(calls.value == 0)
        #expect(session.hasRated == false)
        #expect(viewModel.ratingModel == nil)
    }

    @Test("delete clears hasRated so a later close can ask again")
    func deleteClearsRating() async throws {
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in }
        )
        _ = viewModel.beginRating()
        try await viewModel.submitRating(score: 5, feedback: nil)
        #expect(session.hasRated == true)

        try await viewModel.delete()
        #expect(session.hasRated == false)
        #expect(viewModel.ratingModel == nil)
    }

    @Test("a transport failure leaves the sheet open for retry")
    func submitFailureKeepsSheet() async throws {
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in
                throw ChatServiceError.transport(.http(.unhandled(status: 500)))
            }
        )
        _ = viewModel.beginRating()

        try await viewModel.submitRating(score: 2, feedback: "Broken")

        #expect(session.hasRated == false)
        if case .failed(let score, let feedback, let message) = viewModel.ratingModel?.phase {
            #expect(score == 2)
            #expect(feedback == "Broken")
            #expect(message == L10n.ratingFailed.string)
        } else {
            Issue.record("expected failed phase")
        }
    }

    @Test("session expiry on rate rethrows SessionEnded")
    func submitSessionExpired() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            rateConversation: { _ in throw ChatServiceError.sessionExpired }
        )
        _ = viewModel.beginRating()

        do {
            try await viewModel.submitRating(score: 4, feedback: nil)
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            // expected
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
    }

    @Test("reset clears hasRated so a new conversation can be rated")
    func resetClearsRating() async throws {
        let session = RatingSession()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            ratingSession: session,
            rateConversation: { _ in }
        )
        _ = viewModel.beginRating()
        try await viewModel.submitRating(score: 5, feedback: nil)
        #expect(session.hasRated == true)

        await viewModel.reset()
        #expect(session.hasRated == false)
    }

    @Test("scores 1–3 open the feedback step; 4–5 skip it")
    func pickRoutesByScore() {
        let model = RatingSubmissionModel()
        #expect(model.pick(2) == true)
        if case .feedback(let score) = model.phase {
            #expect(score == 2)
        } else {
            Issue.record("expected feedback")
        }

        let high = RatingSubmissionModel()
        #expect(high.pick(5) == false)
        #expect(high.phase == .picking)
        #expect(high.isFeedbackStep == false)

        let low = RatingSubmissionModel()
        #expect(low.isFeedbackStep == false)
        #expect(low.pick(2) == true)
        #expect(low.isFeedbackStep == true)
    }

    // MARK: - Helpers

    private static func snapshotWithUserTurn() -> ConversationSnapshot {
        ConversationSnapshot(
            turns: [
                Identified(model: .bot([.text(AttributedString("Hi"))])),
                Identified(model: .user([.text(AttributedString("Hello"))])),
                Identified(model: .bot([.text(AttributedString("How can I help?"))])),
            ],
            streamingTurnID: nil,
            canLoadOlder: false
        )
    }

    private static func waitForSnapshot(_ viewModel: ChatView.ViewModel) async {
        for _ in 0..<20 {
            if viewModel.snapshot != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class RatingRequestBox: @unchecked Sendable {
    var value: RateConversationRequest?
}

private final class RatingCallCount: @unchecked Sendable {
    var value = 0
}
