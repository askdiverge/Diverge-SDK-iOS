//
//  ChatViewModelLivechatHandoverTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

extension ChatViewModelLivechatTests {

    // MARK: Handover and close

    @Test("the control queues the visitor with the native client context")
    func controlRequestsHandover() async throws {
        let (viewModel, service, _) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)
        viewModel.startLivechat(with: try Self.config(configured: false))

        await viewModel.toggleLivechat()

        #expect(service.livechatHandoverCallCount == 1)
        #expect(service.lastLivechatHandoverClientContext?.os != nil)
        #expect(!viewModel.isLivechatBusy)
        try await eventually { viewModel.livechatStatus == .waiting }
        #expect(viewModel.livechatControl == .end)
    }

    @Test("a 409 on handover says livechat is offline")
    func handoverConflictIsOffline() async throws {
        let (viewModel, _, _) = self.makeSUT(.init(livechatHandoverError: .conflict))
        viewModel.startLivechat(with: try Self.config(configured: false))

        await viewModel.toggleLivechat()

        #expect(viewModel.notice?.message == L10n.livechatOffline.string)
        #expect(viewModel.livechatStatus == .inactive)
    }

    @Test("an offline control still asks the server, so livechat that came online since launch is reached")
    func offlineControlAsks() async throws {
        let (viewModel, service, _) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)
        viewModel.startLivechat(with: try Self.config(configured: false, live: false))

        await viewModel.toggleLivechat()

        #expect(service.livechatHandoverCallCount == 1)
        #expect(viewModel.notice == nil)
        try await eventually { viewModel.livechatStatus == .waiting }
    }

    @Test("during a session the control asks first, and closes it only once the visitor confirms")
    func controlEndsSession() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)

        await viewModel.toggleLivechat()

        #expect(viewModel.isConfirmingLivechatEnd)
        #expect(service.livechatCloseCallCount == 0)

        await viewModel.confirmEndLivechat()

        #expect(!viewModel.isConfirmingLivechatEnd)
        #expect(service.livechatCloseCallCount == 1)
        #expect(service.lastLivechatCloseReason == "Switched back to AI chatbot mode")
        try await eventually { viewModel.livechatStatus == .closed }
    }

    @Test("a 409 on close reads the real state instead of failing")
    func closeConflictRefreshes() async throws {
        let (viewModel, service, _) = self.makeSUT(.init(livechatCloseError: .conflict))
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .inactive)

        await viewModel.toggleLivechat()
        await viewModel.confirmEndLivechat()

        try await eventually { viewModel.livechatStatus == .inactive }
        #expect(viewModel.notice == nil)
    }

    @Test("a session that ends under the question takes it away, and a late answer queues nothing")
    func endedSessionCancelsTheQuestion() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        await viewModel.toggleLivechat()

        service.livechatState = LivechatState(status: .closed)
        await viewModel.livechat.refresh()
        try await eventually { !viewModel.isConfirmingLivechatEnd }
        await viewModel.confirmEndLivechat()

        #expect(service.livechatCloseCallCount == 0)
        #expect(service.livechatHandoverCallCount == 0)
    }

    @Test("an agent who joins while the visitor is asked about leaving the queue takes the question down and keeps the chat")
    func agentJoiningCancelsTheQuestion() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .waiting, on: service)
        await viewModel.toggleLivechat()
        #expect(viewModel.isConfirmingLivechatEnd)

        service.livechatState = LivechatState(status: .active)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .active }
        #expect(!viewModel.isConfirmingLivechatEnd)

        await viewModel.confirmEndLivechat()

        #expect(service.livechatCloseCallCount == 0)
        #expect(viewModel.livechatStatus == .active)
    }

    @Test("the question asks about the agent during a chat, and the queue while waiting")
    func confirmationCopyFollowsTheSession() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        #expect(viewModel.livechatEndConfirmation.title == L10n.livechatEndTitle.string)

        service.livechatState = LivechatState(status: .waiting)
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .waiting }

        #expect(viewModel.livechatEndConfirmation.title == L10n.livechatLeaveTitle.string)
    }

    @Test("the leave question exists in every locale")
    func leaveCopyExistsInEveryLocale() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "livechat.leaveTitle", "livechat.leaveMessage", "livechat.leaveConfirm", "livechat.leaveCancel",
            "livechat.endTitle", "livechat.endMessage", "livechat.endCancel"
        ])
    }

    // MARK: Reset and delete

    @Test("a reset closes the open session first, then tears livechat down")
    func resetClosesFirst() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)

        await viewModel.reset()

        #expect(service.livechatCloseCallCount == 1)
        #expect(service.lastLivechatCloseReason == "Chat reset")
        #expect(provider.resetCount == 1)
        try await eventually { viewModel.livechatStatus == .inactive }
    }

    @Test("a reset during a send to the agent does nothing, so the session stays open")
    func resetDuringSendKeepsSession() async throws {
        let provider = StubChatProviding()
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .active, on: service)
        provider.whileSendingLivechat = { await viewModel.reset() }

        viewModel.currentMessage = "hi"
        try await viewModel.send()

        #expect(provider.lastLivechatSent == "hi")
        #expect(service.livechatCloseCallCount == 0)
        #expect(provider.resetCount == 0)
        #expect(viewModel.livechatStatus == .active)
    }

    @Test("a second send while one is in flight keeps its text and says to wait")
    func overlappingSendKeepsText() async throws {
        let provider = StubChatProviding()
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .active, on: service)
        provider.whileSendingLivechat = {
            viewModel.currentMessage = "two"
            do {
                try await viewModel.send()
            } catch {
                Issue.record("the second send should bounce, not end the session")
            }
        }

        viewModel.currentMessage = "one"
        try await viewModel.send()

        #expect(provider.lastLivechatSent == "one")
        #expect(viewModel.currentMessage == "two")
        #expect(viewModel.notice?.message == L10n.noticeBusy.string)
    }

    @Test("the handover control waits while a reply streams, so the agent's context holds the reply")
    func handoverWaitsForReply() async throws {
        let provider = StubChatProviding()
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        viewModel.startLivechat(with: try Self.config())
        provider.publish(ConversationSnapshot(
            user: [Identified(model: [.text(AttributedString("hi"))])],
            incoming: [],
            isUserInitiatedConversation: true,
            streamingTurnID: UUID(),
            canLoadOlder: false
        ))
        try await eventually { viewModel.snapshot != nil }

        #expect(viewModel.livechatControl == .start)
        #expect(!viewModel.isLivechatControlEnabled)
        await viewModel.toggleLivechat()

        #expect(service.livechatHandoverCallCount == 0)
    }

    @Test("a delete while the host's page context loads stops the handover")
    func deleteDuringHandoverContext() async throws {
        let entered = AsyncGate()
        let release = AsyncGate()
        let service = MockChatService()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            livechat: LivechatSession(service: service) { _ in throw CancellationError() },
            contextProvider: {
                await entered.open()
                await release.wait()
                return "/orders"
            }
        )
        viewModel.startLivechat(with: try Self.config())
        let handover = Task { await viewModel.toggleLivechat() }
        await entered.wait()

        try await viewModel.delete()
        await release.open()
        await handover.value

        #expect(service.livechatHandoverCallCount == 0)
    }

    @Test("the view model's livechat session is released with it, even while polling is paused")
    func sessionReleasedWithViewModel() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        weak var released: LivechatSession?
        var viewModel: ChatView.ViewModel?
        do {
            let livechat = LivechatSession(service: service) { _ in }
            released = livechat
            viewModel = .forTesting(provider: StubChatProviding(), livechat: livechat)
        }
        viewModel?.startLivechat(with: try Self.config())
        try await eventually { viewModel?.livechatStatus == .active }
        await viewModel?.setVisible(false)
        try await Task.sleep(for: .milliseconds(50))

        viewModel = nil

        try await eventually { released == nil }
    }

    @Test("a reset with no session open closes nothing")
    func resetWithoutSession() async {
        let (viewModel, service, provider) = self.makeSUT()

        await viewModel.reset()

        #expect(service.livechatCloseCallCount == 0)
        #expect(provider.resetCount == 1)
    }

    @Test(
        "a reset goes on when the close finds nothing open or is refused",
        arguments: [ChatServiceError.conflict, .transport(.http(.unhandled(status: 403, body: Data())))]
    )
    func resetAfterSettledClose(_ error: ChatServiceError) async throws {
        let (viewModel, service, provider) = self.makeSUT(.init(livechatCloseError: error))
        try await self.start(viewModel, in: .waiting, on: service)

        await viewModel.reset()

        #expect(provider.resetCount == 1)
        try await eventually { viewModel.livechatStatus == .inactive }
    }

    @Test("a reset stops with a notice when the close fails in a way a retry could fix")
    func resetStopsOnTransientClose() async throws {
        let (viewModel, service, provider) = self.makeSUT(.init(
            livechatCloseError: .transport(.connection(URLError(.notConnectedToInternet)))
        ))
        try await self.start(viewModel, in: .active, on: service)

        await viewModel.reset()

        #expect(provider.resetCount == 0)
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
        #expect(viewModel.livechatStatus == .active)
    }

    @Test("a delete tears livechat down")
    func deleteTearsDown() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)

        try await viewModel.delete()

        try await eventually { viewModel.livechatStatus == .inactive }
        #expect(service.livechatCloseCallCount == 0)
    }

    @Test("a delete that fails leaves the livechat session as it was")
    func failedDeleteKeepsSession() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        try await eventually { provider.notes.count == 1 }
        provider.deleteError = ChatServiceError.transport(.connection(URLError(.timedOut)))

        await #expect(throws: ChatView.DeletionFailed.self) {
            try await viewModel.delete()
        }

        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.livechatStatus == .active)
        #expect(provider.notes.count == 1)
    }

    @Test("a delete while a send is in flight is refused and leaves livechat running")
    func deleteDuringSendIsRefused() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        let deleted = Recorder<Bool>()
        provider.whileSendingLivechat = {
            do {
                try await viewModel.delete()
                deleted.record(true)
            } catch {
                deleted.record(false)
            }
        }
        viewModel.editDraft("hi")

        try await viewModel.send()

        #expect(deleted.values == [false])
        #expect(viewModel.livechatStatus == .active)
    }

    @Test("a reset that fails after closing the session says so")
    func failedResetAfterCloseShowsNotice() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        provider.resetError = ChatServiceError.transport(.connection(URLError(.timedOut)))
        try await self.start(viewModel, in: .active, on: service)

        await viewModel.reset()

        #expect(service.livechatCloseCallCount == 1)
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
    }
}
