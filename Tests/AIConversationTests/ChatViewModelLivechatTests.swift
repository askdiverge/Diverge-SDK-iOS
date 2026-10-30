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
            "livechat.agentFallback", "livechat.agentTyping", "livechat.agentTypingNamed",
            "media.openHint", "media.unavailable",
            "sessionForm.title", "sessionForm.description", "sessionForm.save",
            "sessionForm.saving", "sessionForm.saved", "sessionForm.failed"
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

    @Test("an active agent's typing flag shows on the view model")
    func agentTypingFlag() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        let state = try LivechatFixtures.decoder.decode(LivechatState.self, from: Data("""
        {
          "status": "active",
          "active_agent": { "agent_id": "a", "display_name": "Alice", "avatar_url": null },
          "is_agent_typing": true,
          "feedback": { "status": "not_available" }
        }
        """.utf8))
        service.livechatState = state
        await viewModel.livechat.refresh()

        try await eventually { viewModel.isAgentTyping }
        #expect(viewModel.livechatAgentName == "Alice")
    }

    @Test("while an agent is connected, editing posts true once, and sending posts false")
    func visitorTypingPosts() async throws {
        let (viewModel, service, _) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)

        viewModel.editDraft("h")
        viewModel.editDraft("hi")
        try await eventually { service.livechatTypingEvents == [true] }

        try await viewModel.send()

        try await eventually { service.livechatTypingEvents == [true, false] }
    }

    @Test("a draft put back after a failed send reports no typing")
    func restoredDraftIsNotTyping() async throws {
        let provider = StubChatProviding(livechatSendFailure: .retry(popped: .init(text: "hi", attachments: []), body: nil))
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .active, on: service)
        viewModel.editDraft("hi")
        try await eventually { service.livechatTypingEvents == [true] }

        try await viewModel.send()
        try await eventually { service.livechatTypingEvents == [true, false] }
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.currentMessage == "hi")
        #expect(service.livechatTypingEvents == [true, false])
    }

    @Test("editing without an agent session reports no typing")
    func typingWithoutSession() async throws {
        let (viewModel, service, _) = self.makeSUT()

        viewModel.editDraft("hello")
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.currentMessage == "hello")
        #expect(service.livechatTypingEvents.isEmpty)
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
        let provider = StubChatProviding(sendFailure: .livechatActive(popped: .init(text: "hi", attachments: [])))
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
        let provider = StubChatProviding(sendFailure: .livechatActive(popped: .init(text: "hi", attachments: [])))
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
        let provider = StubChatProviding(livechatSendFailure: .livechatInactive(popped: .init(text: "hi", attachments: [])))
        let (viewModel, service, _) = self.makeSUT(provider: provider)
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)

        viewModel.currentMessage = "hi"
        try await viewModel.send()

        #expect(viewModel.currentMessage == "hi")
        #expect(viewModel.notice?.message == L10n.noticeLivechatEnded.string)
        try await eventually { viewModel.livechatStatus == .closed }
    }
}

extension ChatViewModelLivechatTests {

    /// Publishes a bot turn holding a `request_human_agent` card and returns the turn's id.
    func showPrompt(on provider: StubChatProviding, in viewModel: ChatView.ViewModel) async throws -> UUID {
        let card = Identified<[ChatResponse]>(model: [.requestHumanAgent(.init(partId: "part_human_1"))])
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [card],
            isUserInitiatedConversation: false,
            streamingTurnID: nil,
            canLoadOlder: false
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
