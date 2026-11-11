//
//  ChatViewModelLivechatAttachmentTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

extension ChatViewModelLivechatTests {

    // MARK: Attachment links

    @Test("a temporary attachment link is re-signed from the livechat log when tapped")
    func expiredLinkIsResigned() async throws {
        let (viewModel, service, _) = self.makeSUT()
        let stale = try LivechatFixtures.file(attachmentId: "att_1", expiresAt: "2000-01-01T00:00:00Z")
        let fresh = try LivechatFixtures.file(
            url: "https://cdn.example.com/order.pdf?token=new",
            attachmentId: "att_1",
            expiresAt: "2099-01-01T00:00:00Z"
        )
        service.livechatMessagePages = [LivechatFixtures.page(LivechatFixtures.fileMessage("m1", file: fresh))]

        #expect(await viewModel.url(toOpen: stale) == fresh.url)
    }

    @Test("an expired photo link is re-signed from the livechat log when tapped, as a file's is")
    func expiredImageIsResigned() async {
        let (viewModel, service, _) = self.makeSUT()
        let stale = MessageImage(
            url: URL(string: "https://cdn.example.com/a.jpg?token=old")!,
            attachmentId: "img_1",
            urlExpiresAt: "2000-01-01T00:00:00Z"
        )
        let fresh = MessageImage(
            url: URL(string: "https://cdn.example.com/a.jpg?token=new")!,
            attachmentId: "img_1",
            urlExpiresAt: "2099-01-01T00:00:00Z"
        )
        service.livechatMessagePages = [LivechatFixtures.page(LivechatMessage(
            messageId: "m1",
            role: .agent,
            agent: nil,
            parts: [.image(fresh)],
            createdAt: "2026-01-01T00:00:00Z",
            sequenceNumber: 1
        ))]

        #expect(await viewModel.url(toOpen: stale) == fresh.url)
    }

    @Test("a lasting link opens as stored, and a valid link the log can't re-sign falls back to the stored one")
    func storedLinkFallbacks() async throws {
        let (viewModel, service, _) = self.makeSUT()
        let lasting = try LivechatFixtures.file()
        let unknown = try LivechatFixtures.file(attachmentId: "att_gone", expiresAt: "2099-01-01T00:00:00Z")

        #expect(await viewModel.url(toOpen: lasting) == lasting.url)
        #expect(service.livechatSyncCallCount == 0)
        #expect(await viewModel.url(toOpen: unknown) == unknown.url)
        #expect(service.livechatSyncCallCount == 1)
    }

    @Test("an expired link the log can't re-sign, from an earlier session, isn't opened")
    func expiredUnresignedLinkIsNotOpened() async throws {
        let (viewModel, _, _) = self.makeSUT()
        let earlier = try LivechatFixtures.file(attachmentId: "att_earlier", expiresAt: "2000-01-01T00:00:00Z")

        #expect(await viewModel.url(toOpen: earlier) == nil)
    }

    @Test("an expired photo link the log can't re-sign, from an earlier session, isn't opened")
    func expiredUnresignedImageIsNotOpened() async {
        let (viewModel, _, _) = self.makeSUT()
        let earlier = MessageImage(
            url: URL(string: "https://cdn.example.com/a.jpg?token=old")!,
            attachmentId: "img_earlier",
            urlExpiresAt: "2000-01-01T00:00:00Z"
        )

        #expect(await viewModel.url(toOpen: earlier) == nil)
    }

    @Test("a photo tap whose chat closed while the log was read opens nothing")
    func cancelledImageTapOpensNothing() async throws {
        let (viewModel, service, _) = self.makeSUT()
        let lasting = MessageImage(
            url: URL(string: "https://cdn.example.com/a.jpg?token=old")!,
            attachmentId: "img_1",
            urlExpiresAt: "2099-01-01T00:00:00Z"
        )
        let entered = AsyncGate()
        let release = AsyncGate()
        service.livechatSyncHold = {
            await entered.open()
            await release.wait()
        }

        let tap = Task { await viewModel.url(toOpen: lasting) }
        await entered.wait()
        tap.cancel()
        await release.open()

        #expect(await tap.value == nil)
    }

    @Test("a tap whose chat closed while the log was read opens nothing")
    func cancelledTapOpensNothing() async throws {
        let (viewModel, service, _) = self.makeSUT()
        let lasting = try LivechatFixtures.file(attachmentId: "att_1", expiresAt: "2099-01-01T00:00:00Z")
        let entered = AsyncGate()
        let release = AsyncGate()
        service.livechatSyncHold = {
            await entered.open()
            await release.wait()
        }

        let tap = Task { await viewModel.url(toOpen: lasting) }
        await entered.wait()
        tap.cancel()
        await release.open()

        #expect(await tap.value == nil)
    }

    @Test("an open session found at start says where it stands, once")
    func restoredSessionSaysWhereItStands() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        service.livechatState = try LivechatFixtures.activeState(agentName: "Alice")

        viewModel.startLivechat(with: try Self.config())
        try await eventually { viewModel.livechatStatus == .active }
        try await eventually { !provider.notes.isEmpty }
        await viewModel.livechat.refresh()

        #expect(provider.notes.map(\.kind) == [.agentJoined(displayName: "Alice")])
    }

    @Test("a queue found at start says so")
    func restoredQueueSaysSo() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        service.livechatState = LivechatState(status: .waiting)

        viewModel.startLivechat(with: try Self.config())

        try await eventually { provider.notes.map(\.kind) == [.queued] }
    }

    @Test("a closed session found at start notes nothing")
    func restoredCloseNotesNothing() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        service.livechatState = LivechatState(status: .closed)

        viewModel.startLivechat(with: try Self.config())

        try await eventually { viewModel.livechatStatus == .closed }
        #expect(provider.notes.isEmpty)
    }

    @Test("the ended note follows the agent's last messages")
    func endedNoteFollowsMessages() async throws {
        let (viewModel, service, provider) = self.makeSUT()
        try await self.start(viewModel, in: .active, on: service)
        service.livechatState = LivechatState(status: .closed)
        service.livechatMessagePages = [.init(messages: []), LivechatFixtures.page(LivechatFixtures.message("bye", role: .agent))]

        await viewModel.livechat.refresh()

        try await eventually { provider.livechatOrder.suffix(2) == ["message:bye", "note:ended"] }
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
            user: [Identified(model: [.text(AttributedString("hi"))])],
            incoming: [card, Identified(model: [.text(AttributedString("later"))])],
            isUserInitiatedConversation: false,
            streamingTurnID: nil,
            canLoadOlder: false
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
            user: [Identified(model: [.text(AttributedString("hi"))])],
            incoming: [card],
            isUserInitiatedConversation: true,
            streamingTurnID: card.id,
            canLoadOlder: false
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
}
