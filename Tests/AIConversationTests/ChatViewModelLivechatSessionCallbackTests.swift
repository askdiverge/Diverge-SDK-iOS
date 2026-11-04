//
//  ChatViewModelLivechatSessionCallbackTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// What the host's `onLivechatSessionChange` hears, driven by `LivechatSession` snapshots over
/// `MockChatService`; no server is involved.
@Suite("ChatView.ViewModel — onLivechatSessionChange")
@MainActor
struct LivechatSessionCallbackTests {

    @Test("the host hears each phase once, with the agent's name while active")
    func phasesWithAgentName() async throws {
        let (viewModel, service, infos) = self.makeSUT()

        try await self.start(viewModel, in: .waiting, on: service)
        service.livechatState = try LivechatFixtures.activeState(agentName: "Alice")
        await viewModel.livechat.refresh()
        try await eventually { infos.count == 2 }

        service.livechatState = try LivechatFixtures.decoder.decode(LivechatState.self, from: Data("""
        {
          "status": "active",
          "active_agent": { "agent_id": "a", "display_name": "Alice", "avatar_url": null },
          "is_agent_typing": true,
          "feedback": { "status": "not_available" }
        }
        """.utf8))
        await viewModel.livechat.refresh()
        service.livechatState = LivechatState(status: .closed)
        await viewModel.livechat.refresh()

        try await eventually { infos.count == 3 }
        #expect(infos.values == [
            AIChat.LivechatSessionInfo(status: .waiting),
            AIChat.LivechatSessionInfo(status: .active, agentDisplayName: "Alice"),
            AIChat.LivechatSessionInfo(status: .closed)
        ])
    }

    @Test("changes seen while the chat is off screen reach the host once it is back")
    func offScreenChangesWait() async throws {
        let (viewModel, service, infos) = self.makeSUT()
        try await self.start(viewModel, in: .waiting, on: service)
        try await eventually { infos.count == 1 }
        await viewModel.setSceneActive(false)

        service.livechatState = try LivechatFixtures.activeState(agentName: "Alice")
        await viewModel.livechat.refresh()
        try await eventually { viewModel.livechatStatus == .active }
        #expect(infos.count == 1)

        await viewModel.setSceneActive(true)

        #expect(infos.values == [
            AIChat.LivechatSessionInfo(status: .waiting),
            AIChat.LivechatSessionInfo(status: .active, agentDisplayName: "Alice")
        ])
    }

    @Test("a 401 on the poller reports the session inactive")
    func expiryReportsInactive() async throws {
        let (viewModel, service, infos) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)

        service.livechatStateError = .sessionExpired
        await viewModel.livechat.refresh()

        try await eventually { infos.values.last == AIChat.LivechatSessionInfo(status: .inactive) }
    }

    @Test("the agent's name is kept only while active, and a blank one is dropped")
    func agentNameOnlyWhileActive() {
        #expect(AIChat.LivechatSessionInfo(status: .active, agentDisplayName: "  Alice ").agentDisplayName == "Alice")
        #expect(AIChat.LivechatSessionInfo(status: .active, agentDisplayName: "   ").agentDisplayName == nil)
        #expect(AIChat.LivechatSessionInfo(status: .closed, agentDisplayName: "Alice").agentDisplayName == nil)
    }
}

private extension LivechatSessionCallbackTests {

    func makeSUT() -> (viewModel: ChatView.ViewModel, service: MockChatService, infos: Recorder<AIChat.LivechatSessionInfo>) {
        let service = MockChatService()
        let infos = Recorder<AIChat.LivechatSessionInfo>()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { infos.record($0) },
            // Ends the poll loop at its first wait, so only the reads a test triggers run.
            livechat: LivechatSession(service: service) { _ in throw CancellationError() }
        )
        return (viewModel, service, infos)
    }

    func start(_ viewModel: ChatView.ViewModel, in status: LivechatState.Status, on service: MockChatService) async throws {
        service.livechatState = LivechatState(status: status)
        viewModel.startLivechat(with: try LivechatFixtures.decoder.decode(
            LivechatConfig.self,
            from: Data(#"{"enabled":true,"configured":true,"availability_status":"live"}"#.utf8)
        ))
        try await eventually { viewModel.livechatStatus == status }
    }
}
