//
//  ChatProviderHistoryTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — history pages")
struct ChatProviderHistoryTests {

    @Test("a first page asked for again after the conversation moved on shows it as the server has it, once")
    func lateFirstPageShowsTheConversationOnce() async throws {
        let mock = MockChatService(.init(
            sendEvents: Self.reply("r1", "hello"),
            historyPages: [
                MessagePage(messages: [], nextCursor: nil),
                MessagePage(messages: [
                    Self.message("r1", .assistant, "hello"),
                    Self.message("u1", .user, "hi"),
                    Self.message("a0", .assistant, "earlier answer"),
                    Self.message("u0", .user, "earlier question")
                ], nextCursor: nil)
            ],
            historyFailingCalls: [0: Self.serverError]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatServiceError.self) { try await provider.loadOlder() }
        try await provider.send("hi")
        try await provider.loadOlder()

        #expect(await snapshots.next()?.turns.map(\.model) == [
            .user([.text(AttributedString("earlier question"))]),
            .bot([.text(AttributedString("earlier answer"))]),
            .user([.text(AttributedString("hi"))]),
            .bot([.text(AttributedString("hello"))])
        ])
    }

    @Test("livechat messages shown before a late first page appear once, and the newer ones stay after it")
    func lateFirstPageKeepsLivechatOnce() async throws {
        let mock = MockChatService(.init(
            historyPages: [
                MessagePage(messages: [], nextCursor: nil),
                MessagePage(messages: [
                    Self.message("h-u1", .user, "my order", createdAt: "2026-01-01T00:00:02.000Z"),
                    Self.message("h-a1", .agent, "agent here", createdAt: "2026-01-01T00:00:01.000Z")
                ], nextCursor: nil)
            ],
            historyFailingCalls: [0: Self.serverError]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatServiceError.self) { try await provider.loadOlder() }
        await provider.appendLivechat([
            LivechatFixtures.message("l-a1", role: .agent, text: "agent here", sequence: 1, createdAt: "2026-01-01T00:00:01.000Z"),
            LivechatFixtures.message("l-u1", role: .user, text: "my order", sequence: 2, createdAt: "2026-01-01T00:00:02.000Z"),
            LivechatFixtures.message("l-a2", role: .agent, text: "thanks", sequence: 3, createdAt: "2026-01-01T00:00:03.000Z")
        ])
        try await provider.loadOlder()

        #expect(await snapshots.next()?.turns.map(\.model) == [
            .bot([.text(AttributedString("agent here"))]),
            .user([.text(AttributedString("my order"))]),
            .bot([.text(AttributedString("thanks"))])
        ])
    }

    @Test("a first page asked for again while a message is on its way waits for it, and can be asked for later")
    func lateFirstPageWaitsForASend() async throws {
        let mock = MockChatService(.init(
            sendEvents: Self.reply("r1", "hello"),
            historyPages: [
                MessagePage(messages: [], nextCursor: nil),
                MessagePage(messages: [
                    Self.message("r1", .assistant, "hello"),
                    Self.message("u1", .user, "hi")
                ], nextCursor: nil)
            ],
            historyFailingCalls: [0: Self.serverError]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        let entered = AsyncGate()
        let release = AsyncGate()
        mock.sendHold = {
            await entered.open()
            await release.wait()
        }
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatServiceError.self) { try await provider.loadOlder() }
        let send = Task { try await provider.send("hi") }
        await entered.wait()
        try await provider.loadOlder()
        #expect(mock.historyCallCount == 1)
        await release.open()
        try await send.value
        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.map(\.model) == [
            .user([.text(AttributedString("hi"))]),
            .bot([.text(AttributedString("hello"))])
        ])
        #expect(snapshot?.canLoadOlder == false)
        #expect(mock.historyCallCount == 2)
    }

    @Test("a page that arrives after a reset is dropped, and the new conversation keeps its own paging")
    func pageAfterResetIsDropped() async throws {
        let gate = AsyncGate()
        let mock = MockChatService(.init(
            historyPages: [
                MessagePage(messages: [Self.message("o1", .assistant, "old")], nextCursor: "old-cursor"),
                MessagePage(messages: [Self.message("n1", .assistant, "new")], nextCursor: nil)
            ],
            historyGates: [0: gate]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        var snapshots = provider.stream.makeAsyncIterator()

        let load = Task { try await provider.loadOlder() }
        try await eventually { mock.historyCallCount == 1 }
        try await provider.reset()
        await gate.open()
        try await load.value
        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("new"))]])
        #expect(snapshot?.canLoadOlder == false)
        #expect(mock.historyCallCount == 2)
    }

    @Test("a page that arrives after a delete doesn't bring the deleted messages back")
    func pageAfterDeleteIsDropped() async throws {
        let gate = AsyncGate()
        let mock = MockChatService(.init(
            historyPages: [MessagePage(messages: [Self.message("d1", .assistant, "deleted")], nextCursor: nil)],
            historyGates: [0: gate]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, acceptsImageUploadPrompts: true)
        var snapshots = provider.stream.makeAsyncIterator()

        let load = Task { try await provider.loadOlder() }
        try await eventually { mock.historyCallCount == 1 }
        try await provider.delete()
        await gate.open()
        try await load.value

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming == [])
        #expect(snapshot?.canLoadOlder == false)
    }
}

private extension ChatProviderHistoryTests {

    static let serverError = ChatServiceError.transport(.http(.unhandled(status: 500, body: Data())))

    /// A stored message `id` carrying a single paragraph of `text`.
    static func message(
        _ id: String,
        _ role: Message.Role,
        _ text: String,
        createdAt: String = "2026-01-01T00:00:00.000Z"
    ) -> Message {
        Message(
            messageId: id,
            role: role,
            agent: nil,
            parts: [.richText(RichText(partId: id, blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: createdAt
        )
    }

    /// The events of a reply that streams `text` and is stored as message `id`.
    static func reply(_ id: String, _ text: String) -> [StreamEvent] {
        let message = Self.message(id, .assistant, text)
        return message.parts.map(StreamEvent.part) + [.done(message)]
    }
}
