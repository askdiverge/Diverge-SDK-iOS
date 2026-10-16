//
//  ChatViewModelLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — livechat handover")
@MainActor
struct ChatViewModelLivechatTests {

    // MARK: Start

    @Test("a configured livechat reads the session at start, and an open session's messages join the conversation")
    func startReadsOpenSession() async throws {
        let message = LivechatFixtures.message("a1", role: .agent, text: "Hi, I'm Alice")
        let (viewModel, service, provider) = self.makeSUT(.init(
            livechatState: LivechatState(status: .active),
            livechatMessagePages: [LivechatFixtures.page(message)]
        ))

        viewModel.startLivechat(with: try Self.config())

        try await eventually { provider.appendedLivechat.map(\.messageId) == ["a1"] }
        #expect(viewModel.livechatStatus == .active)
        #expect(service.livechatSyncCallCount == 1)
    }

    @Test("livechat that isn't configured is never read")
    func unconfiguredIsNeverRead() async throws {
        let (viewModel, service, _) = self.makeSUT()

        viewModel.startLivechat(with: try Self.config(configured: false))
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.livechatSyncCallCount == 0)
    }

    @Test("a session that ended on the poller (401) clears the conversation and asks for the alert")
    func expiryEndsTheChat() async throws {
        let (viewModel, _, provider) = self.makeSUT(.init(livechatStateError: .sessionExpired))

        viewModel.startLivechat(with: try Self.config())

        try await eventually { viewModel.livechatSessionEnded }
        #expect(provider.expireCount == 1)
    }

    // MARK: Header control and placeholder

    @Test("the header control shows only while livechat is enabled with its logo, and is offline when unavailable")
    func controlFromConfig() throws {
        let (viewModel, _, _) = self.makeSUT()
        #expect(viewModel.livechatControl == .hidden)

        viewModel.startLivechat(with: try Self.config(enabled: false, configured: false))
        #expect(viewModel.livechatControl == .hidden)

        viewModel.startLivechat(with: try Self.config(configured: false, showsLogo: false))
        #expect(viewModel.livechatControl == .hidden)

        viewModel.startLivechat(with: try Self.config(configured: false))
        #expect(viewModel.livechatControl == .start)

        viewModel.startLivechat(with: try Self.config(configured: false, live: false))
        #expect(viewModel.livechatControl == .offline)
    }

    @Test("during a session the control ends it, even with livechat switched off")
    func controlDuringSession() async throws {
        let (viewModel, service, _) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)

        viewModel.startLivechat(with: try Self.config(enabled: false))

        try await eventually { viewModel.livechatStatus == .waiting }
        #expect(viewModel.livechatControl == .end)
    }

    @Test("the composer placeholder names who the next message goes to")
    func placeholderPerStatus() async throws {
        let expected: [(LivechatState.Status, LocalizedStringResource)] = [
            (.inactive, L10n.inputPlaceholder),
            (.waiting, L10n.livechatWaitingPlaceholder),
            (.active, L10n.livechatActivePlaceholder),
            (.closed, L10n.livechatClosedPlaceholder)
        ]
        var placeholders: Set<String> = []
        for (status, copy) in expected {
            let (viewModel, service, _) = self.makeSUT()
            try await self.start(viewModel, in: status, on: service)
            #expect(viewModel.inputPlaceholder == copy.string)
            placeholders.insert(viewModel.inputPlaceholder)
        }
        #expect(placeholders.count == expected.count)
    }

    @Test("livechat copy is translated in every locale")
    func copyInEveryLocale() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "livechat.start", "livechat.end", "livechat.offline",
            "livechat.waitingPlaceholder", "livechat.activePlaceholder", "livechat.closedPlaceholder",
            "livechat.waitingStatus", "livechat.activeStatus",
            "livechat.talkToPerson", "livechat.humanAgentPrompt", "livechat.humanAgentHint",
            "livechat.queuedNote", "livechat.endedNote", "livechat.agentJoinedNote",
            "livechat.agentFallback"
        ])
    }

    // MARK: Notes, typing and the prompt card

    @Test("joining the queue, an agent joining and the session ending each mint a note")
    func statusChangesMintNotes() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        viewModel.startLivechat(with: try Self.config(configured: false))

        service.livechatState = LivechatState(status: .waiting)
        await viewModel.toggleLivechat()
        try await eventually { provider.notes.contains { $0.kind == .queued } }

        service.livechatState = try LivechatFixtures.activeState(agentName: "Alice")
        await viewModel.livechat.refresh()
        try await eventually {
            provider.notes.contains {
                if case .agentJoined(let name) = $0.kind { name == "Alice" } else { false }
            }
        }
        #expect(viewModel.livechatAgentName == "Alice")

        service.livechatState = LivechatState(status: .closed)
        await viewModel.livechat.refresh()
        try await eventually { provider.notes.contains { $0.kind == .ended } }
    }

    @Test("an open session found at start mints no notes")
    func restoredSessionMintsNoNotes() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        service.livechatState = try LivechatFixtures.activeState(agentName: "Alice")

        viewModel.startLivechat(with: try Self.config())

        try await eventually { viewModel.livechatStatus == .active }
        #expect(provider.notes.isEmpty)
    }

    @Test("the ended note follows the agent's last messages")
    func endedNoteFollowsMessages() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)
        service.livechatMessagePages = [.init(messages: []), LivechatFixtures.page(LivechatFixtures.message("bye", role: .agent))]

        await viewModel.livechat.refresh()

        try await eventually { provider.livechatOrder == ["message:bye", "note:ended"] }
    }

    @Test("the talk-to-a-person card hands over once, and not again during the session")
    func promptCardHandsOverOnce() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)
        let turnID = try await self.showPrompt(on: provider, in: viewModel)

        async let first: Void = viewModel.acceptHumanAgentPrompt(partId: "part_human_1", inBotTurn: turnID)
        async let second: Void = viewModel.acceptHumanAgentPrompt(partId: "part_human_1", inBotTurn: turnID)
        _ = await (first, second)
        try await eventually { viewModel.livechatStatus == .waiting }
        await viewModel.acceptHumanAgentPrompt(partId: "part_human_1", inBotTurn: turnID)

        #expect(service.livechatHandoverCallCount == 1)
        #expect(!viewModel.canAcceptHumanAgentPrompt(inBotTurn: turnID))
    }

    @Test("a card in an older bot turn can't hand over")
    func olderPromptCardIsInert() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        let card = Identified<[ChatResponse]>(model: [.requestHumanAgent(.init(partId: "part_human_1"))])
        provider.publish(ConversationSnapshot(
            user: [Identified(model: [AttributedString("hi")])],
            incoming: [card, Identified(model: [.text(AttributedString("later"))])],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))
        try await eventually { viewModel.snapshot != nil }

        await viewModel.acceptHumanAgentPrompt(partId: "part_human_1", inBotTurn: card.id)

        #expect(service.livechatHandoverCallCount == 0)
    }

    @Test("the talk-to-a-person card waits while the reply it came in streams")
    func promptCardWaitsForReply() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        let card = Identified<[ChatResponse]>(model: [.requestHumanAgent(.init(partId: "part_human_1"))])
        provider.publish(ConversationSnapshot(
            user: [Identified(model: [AttributedString("hi")])],
            incoming: [card],
            isUserInitiatedConversation: true,
            streamingTurnID: card.id
        ))
        try await eventually { viewModel.snapshot != nil }

        #expect(!viewModel.canAcceptHumanAgentPrompt(inBotTurn: card.id))
        await viewModel.acceptHumanAgentPrompt(partId: "part_human_1", inBotTurn: card.id)

        #expect(service.livechatHandoverCallCount == 0)
    }

    @Test("the request_human_agent card hands over with the marker's part_id")
    func promptHandoverUsesPartId() async throws {
        let (viewModel, service, _) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)
        viewModel.startLivechat(with: try Self.config(configured: false))

        await viewModel.requestLivechat(partId: "part_human_1")

        #expect(service.livechatHandoverCallCount == 1)
        #expect(service.lastLivechatHandoverSource == .assistantMarker)
        #expect(service.lastLivechatHandoverPartId == "part_human_1")
        try await eventually { viewModel.livechatStatus == .waiting }
    }

    // MARK: Send routing

    @Test("while an agent is connected the composer sends to the agent")
    func sendsToAgentWhileActive() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)

        viewModel.currentMessage = "Here is my order"
        try await viewModel.send()

        #expect(provider.lastLivechatSent == "Here is my order")
        #expect(provider.lastSent == nil)
    }

    @Test("while queued the composer still sends to the assistant")
    func sendsToAssistantWhileWaiting() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .waiting, on: service)

        viewModel.currentMessage = "Where is my parcel?"
        try await viewModel.send()

        #expect(provider.lastSent == "Where is my parcel?")
        #expect(provider.lastLivechatSent == nil)
    }

    @Test("a 409 on the assistant send adopts the active session and resends the text to the agent")
    func assistantConflictAdoptsSession() async throws {
        let provider = StubChatProviding(sendFailure: .livechatActive(popped: "hi"))
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        service.livechatState = LivechatState(status: .active)

        viewModel.currentMessage = "hi"
        try await viewModel.send()

        #expect(provider.lastLivechatSent == "hi")
        #expect(viewModel.currentMessage.isEmpty)
        #expect(viewModel.notice == nil)
        try await eventually { viewModel.livechatStatus == .active }
    }

    @Test("a 409 on the assistant send with no agent session offers a retry and stays with the assistant")
    func assistantConflictWithoutSession() async throws {
        let provider = StubChatProviding(sendFailure: .livechatActive(popped: "hi"))
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        service.livechatState = LivechatState(status: .inactive)

        viewModel.currentMessage = "hi"
        try await viewModel.send()

        #expect(provider.lastLivechatSent == nil)
        #expect(viewModel.currentMessage == "hi")
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
        #expect(service.livechatSyncCallCount == 1)
        #expect(viewModel.livechatStatus == .inactive)
    }

    @Test("a 409 on the agent send says the agent chat ended and refreshes, so the next send goes to the assistant")
    func agentConflictRefreshes() async throws {
        let provider = StubChatProviding(livechatSendFailure: .livechatInactive(popped: "hi"))
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)

        viewModel.currentMessage = "hi"
        try await viewModel.send()

        #expect(viewModel.currentMessage == "hi")
        #expect(viewModel.notice?.message == L10n.noticeLivechatEnded.string)
        try await eventually { viewModel.livechatStatus == .closed }
    }

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

    @Test("during a session the control closes it and returns to the assistant")
    func controlEndsSession() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)

        await viewModel.toggleLivechat()

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

        try await eventually { viewModel.livechatStatus == .inactive }
        #expect(viewModel.notice == nil)
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
            user: [Identified(model: [AttributedString("hi")])],
            incoming: [],
            isUserInitiatedConversation: true,
            streamingTurnID: UUID()
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
}

private extension ChatViewModelLivechatTests {

    /// Publishes a bot turn holding a `request_human_agent` card and returns the turn's id.
    func showPrompt(on provider: StubChatProviding, in viewModel: ChatView.ViewModel) async throws -> UUID {
        let card = Identified<[ChatResponse]>(model: [.requestHumanAgent(.init(partId: "part_human_1"))])
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [card],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))
        try await eventually { viewModel.snapshot?.lastBotTurnID == card.id }
        return card.id
    }

    func makeSUT(
        _ stub: MockChatService.Stub = .init(),
        provider: StubChatProviding = StubChatProviding()
    ) -> (viewModel: ChatView.ViewModel, service: MockChatService, provider: StubChatProviding) {
        let service = MockChatService(stub)
        // Ends the poll loop at its first wait, so only the reads a test triggers run.
        let livechat = LivechatSession(service: service) { _ in throw CancellationError() }
        return (ChatView.ViewModel.forTesting(provider: provider, livechat: livechat), service, provider)
    }

    /// Starts livechat on a session in `status`, as the bootstrap read finds it.
    func start(
        _ viewModel: ChatView.ViewModel,
        in status: LivechatState.Status,
        on service: MockChatService
    ) async throws {
        service.livechatState = LivechatState(status: status)
        viewModel.startLivechat(with: try Self.config())
        try await eventually { viewModel.livechatStatus == status }
    }

    static func config(
        enabled: Bool = true,
        configured: Bool = true,
        live: Bool = true,
        showsLogo: Bool = true
    ) throws -> LivechatConfig {
        try LivechatFixtures.decoder.decode(LivechatConfig.self, from: Data("""
        {
          "enabled": \(enabled),
          "configured": \(configured),
          "availability_status": "\(live ? "live" : "offline")",
          "show_livechat_logo": \(showsLogo)
        }
        """.utf8))
    }
}
