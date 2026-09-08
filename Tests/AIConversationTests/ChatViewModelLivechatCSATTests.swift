//
//  ChatViewModelLivechatCSATTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — livechat CSAT")
@MainActor
struct ChatViewModelLivechatCSATTests {

    @Test("closed + pending offers CSAT; waiting/active clears dismiss")
    func closedPendingOffers() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)

        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .active,
            state: LivechatState(
                status: .closed,
                feedback: LivechatState.Feedback(status: .pending)
            )
        ))
        #expect(vm.livechatCSATPending == true)
        #expect(vm.livechat.feedback.status == .pending)

        // Skip locally
        vm.dismissLivechatCSAT()
        #expect(vm.livechatCSATPending == false)

        // Same closed + pending does not re-offer after dismiss
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .closed,
            state: LivechatState(
                status: .closed,
                feedback: LivechatState.Feedback(status: .pending)
            )
        ))
        #expect(vm.livechatCSATPending == false)

        // New waiting session clears dismiss
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(status: .waiting)
        ))
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .waiting,
            state: LivechatState(
                status: .closed,
                feedback: LivechatState.Feedback(status: .pending)
            )
        ))
        #expect(vm.livechatCSATPending == true)
    }

    @Test("waiting/active does not offer CSAT")
    func inSessionDoesNotOffer() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(
                status: .waiting,
                feedback: LivechatState.Feedback(status: .pending)
            )
        ))
        #expect(vm.livechatCSATPending == false)
    }

    @Test("shouldOfferRating is false while waiting/active or after closed livechat")
    func conversationRatingGated() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Hi"))])),
            Identified(model: .user([.text("hello")])),
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(vm)
        #expect(vm.shouldOfferRating == true)

        vm.setLivechatStatusForTesting(.waiting)
        #expect(vm.shouldOfferRating == false)

        vm.setLivechatStatusForTesting(.active)
        #expect(vm.shouldOfferRating == false)

        vm.setLivechatStatusForTesting(.closed)
        #expect(vm.shouldOfferRating == false)

        vm.setLivechatStatusForTesting(.inactive)
        #expect(vm.shouldOfferRating == true)
    }

    @Test("submitLivechatFeedback success clears draft; conflict treated as success")
    func submitSuccessAndConflict() async throws {
        let calls = CallCount()
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel(
            service: ChatService(
                tokenProvider: { "t" },
                onResetConversation: { "t" },
                onDeleteData: {}
            ),
            contextProvider: nil,
            conversationFlow: .topDown,
            submitLivechatFeedback: { request in
                calls.value += 1
                if calls.value == 1 {
                    return LivechatFeedbackResponse(
                        livechatSessionId: "lc",
                        status: "submitted",
                        rating: request.rating
                    )
                }
                throw ChatServiceError.conflict
            }
        )
        vm.attachProviderForTesting(provider)

        _ = vm.beginRating()
        try await vm.submitLivechatFeedback(score: 5, feedback: nil)
        #expect(vm.ratingModel == nil)
        #expect(vm.livechat.feedback.status == .submitted)
        #expect(vm.ratingSessionHasRated == false)

        _ = vm.beginRating()
        try await vm.submitLivechatFeedback(score: 4, feedback: "x")
        #expect(vm.ratingModel == nil)
        #expect(calls.value == 2)
    }

    @Test("submitLivechatFeedback 401 throws SessionEnded")
    func submit401() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel(
            service: ChatService(
                tokenProvider: { "t" },
                onResetConversation: { "t" },
                onDeleteData: {}
            ),
            contextProvider: nil,
            conversationFlow: .topDown,
            submitLivechatFeedback: { _ in throw ChatServiceError.sessionExpired }
        )
        vm.attachProviderForTesting(provider)
        _ = vm.beginRating()
        do {
            try await vm.submitLivechatFeedback(score: 2, feedback: nil)
            Issue.record("expected SessionEnded")
        } catch let error as ChatView.SessionEnded {
            _ = error
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
        #expect(vm.ratingModel != nil)
    }

    @Test("bootstrap inactive → closed + pending offers CSAT")
    func bootstrapClosedPendingOffersCSAT() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .inactive))
        #expect(vm.livechatCSATPending == true)
        #expect(vm.canOfferLivechatCSAT == true)
        #expect(vm.shouldOfferRating == false)
    }

    @Test("prepareClose while CSAT overlay skips without POST then handoff")
    func closeWhileOverlaySkipsThenHandoff() async {
        let calls = CallCount()
        var onCloseCount = 0
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(
            provider: provider,
            onClose: { onCloseCount += 1 },
            submitLivechatFeedback: { _ in
                calls.value += 1
                return LivechatFeedbackResponse(
                    livechatSessionId: "lc",
                    status: "submitted",
                    rating: 5
                )
            }
        )
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .active))
        _ = vm.beginRating()
        #expect(vm.isLivechatCSATBlockingHandover == true)

        let decision = vm.prepareClose(showingLivechatCSAT: true)
        #expect(decision == .handoffToHost)
        #expect(calls.value == 0)
        #expect(vm.ratingModel == nil)
        #expect(vm.livechatCSATPending == false)
        #expect(onCloseCount == 0)

        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .closed))
        #expect(vm.livechatCSATPending == false)
        #expect(vm.canOfferLivechatCSAT == false)
    }

    @Test("prepareClose offers CSAT when closed + pending and overlay is not showing")
    func closeOffersCSATWhenClosedPending() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .inactive))
        vm.consumeLivechatCSATPending()
        #expect(vm.livechatCSATPending == false)

        let decision = vm.prepareClose(showingLivechatCSAT: false)
        #expect(decision == .presentLivechatCSAT)
        #expect(vm.livechatCSATPending == true)
    }

    @Test("dismissLivechatCSAT does not POST feedback")
    func skipDoesNotPostFeedback() async {
        let calls = CallCount()
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(
            provider: provider,
            submitLivechatFeedback: { _ in
                calls.value += 1
                return LivechatFeedbackResponse(
                    livechatSessionId: "lc",
                    status: "submitted",
                    rating: 1
                )
            }
        )
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .active))
        _ = vm.beginRating()
        vm.dismissLivechatCSAT()
        #expect(calls.value == 0)
        #expect(vm.ratingModel == nil)
        #expect(vm.livechatCSATPending == false)
    }

    @Test("waiting while CSAT draft is up dismisses without POST")
    func waitingDismissesCSATWithoutPOST() async {
        let calls = CallCount()
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(
            provider: provider,
            submitLivechatFeedback: { _ in
                calls.value += 1
                return LivechatFeedbackResponse(
                    livechatSessionId: "lc",
                    status: "submitted",
                    rating: 1
                )
            }
        )
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .active))
        _ = vm.beginRating()
        #expect(vm.ratingModel != nil)

        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .closed,
            state: LivechatState(status: .waiting)
        ))
        #expect(vm.ratingModel == nil)
        #expect(calls.value == 0)
        #expect(vm.livechatCSATPending == false)
        #expect(vm.isLivechatCSATBlockingHandover == false)

        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .waiting))
        #expect(vm.livechatCSATPending == true)
    }

    @Test("non-409 transport error keeps ratingModel and does not dismiss CSAT")
    func submitTransportErrorKeepsDraft() async throws {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(
            provider: provider,
            submitLivechatFeedback: { _ in
                throw ChatServiceError.transport(.http(.unhandled(status: 500)))
            }
        )
        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .active))
        _ = vm.beginRating()
        try await vm.submitLivechatFeedback(score: 3, feedback: nil)
        #expect(vm.ratingModel != nil)

        await vm.applyLivechatSnapshotForTesting(Self.closedPending(previous: .closed))
        #expect(vm.livechatCSATPending == true)
        #expect(vm.canOfferLivechatCSAT == true)
    }

    private static func closedPending(previous: LivechatState.Status) -> LivechatSnapshot {
        LivechatSnapshot(
            previousStatus: previous,
            state: LivechatState(
                status: .closed,
                feedback: LivechatState.Feedback(status: .pending)
            )
        )
    }

    private static func waitForSnapshot(_ viewModel: ChatView.ViewModel) async {
        for _ in 0..<20 {
            if viewModel.snapshot != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private final class CallCount: @unchecked Sendable {
    var value = 0
}
