//
//  ChatProviderLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — livechat")
struct ChatProviderLivechatTests {

    @Test("the poller's copy of a message sent from here isn't shown twice")
    func sendRecordsStoredID() async throws {
        let stored = LivechatFixtures.message("lc_1", role: .user, text: "hi")
        let mock = MockChatService(.init(livechatSendResponse: stored))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.sendLivechat("hi")
        await provider.appendLivechat([stored, LivechatFixtures.message("a1", role: .agent, text: "ok")])

        let snapshot = await snapshots.next()
        #expect(snapshot?.user.map(\.model) == [[AttributedString("hi")]])
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("ok"))]])
    }

    @Test("a poll that returns the message while its POST is in flight doesn't duplicate it")
    func pollDuringSendIsHeld() async throws {
        let stored = LivechatFixtures.message("lc_1", role: .user, text: "hi")
        let mock = MockChatService(.init(livechatSendResponse: stored))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        let entered = AsyncGate()
        let release = AsyncGate()
        mock.livechatSendHold = {
            await entered.open()
            await release.wait()
        }
        let send = Task { try await provider.sendLivechat("hi") }
        await entered.wait()

        await provider.appendLivechat([stored])
        await release.open()
        try await send.value

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.user.map(\.model) == [[AttributedString("hi")]])
    }

    @Test("a failed livechat send pops its echo")
    func sendFailurePopsEcho() async {
        let mock = MockChatService(.init(livechatSendError: .transport(.http(.unhandled(status: 500, body: Data())))))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: nil)) {
            try await provider.sendLivechat("hi")
        }

        #expect(await snapshots.next()?.user.isEmpty == true)
    }

    @Test("a 409 on a livechat send surfaces livechatInactive and pops the echo")
    func sendConflict() async {
        let mock = MockChatService(.init(livechatSendError: .conflict))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.livechatInactive(popped: "hi")) {
            try await provider.sendLivechat("hi")
        }

        #expect(await snapshots.next()?.user.isEmpty == true)
    }

    @Test("visitor messages go to the user pane and every other role to the bot pane")
    func roleMapping() async {
        let provider: any ChatProviding = ChatProvider(service: MockChatService(), pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await provider.appendLivechat([
            LivechatFixtures.message("u", role: .user, text: "hi", sequence: 1),
            LivechatFixtures.message("a", role: .agent, text: "hello", sequence: 2),
            LivechatFixtures.message("s", role: .system, text: "closed", sequence: 3)
        ])

        let snapshot = await snapshots.next()
        #expect(snapshot?.user.map(\.model) == [[AttributedString("hi")]])
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("hello")), .text(AttributedString("closed"))]])
    }

    @Test("agent messages in a row join the bot turn, so none drops out of the turns")
    func consecutiveAgentMessagesStayVisible() async throws {
        let provider = try await Self.providerAfterOneExchange()
        var snapshots = provider.stream.makeAsyncIterator()

        await provider.appendLivechat([
            LivechatFixtures.message("a1", role: .agent, text: "one", sequence: 1),
            LivechatFixtures.message("a2", role: .agent, text: "two", sequence: 2)
        ])
        await provider.appendLivechat([LivechatFixtures.message("u1", role: .user, text: "thanks", sequence: 3)])
        await provider.appendLivechat([LivechatFixtures.message("a3", role: .agent, text: "welcome", sequence: 4)])

        let turns = await snapshots.next()?.turns.map(\.model)
        #expect(turns == [
            .user([AttributedString("hi")]),
            .bot([.text(AttributedString("reply")), .text(AttributedString("one")), .text(AttributedString("two"))]),
            .user([AttributedString("thanks")]),
            .bot([.text(AttributedString("welcome"))])
        ])
    }

    @Test("an agent message during a streaming reply waits until the reply settles")
    func agentMessageWaitsForStream() async throws {
        let mock = MockChatService(.init(sendEvents: [Self.textPart("reply")]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        let entered = AsyncGate()
        let release = AsyncGate()
        mock.sendHold = {
            await entered.open()
            await release.wait()
        }
        let send = Task { try await provider.send("hi") }
        await entered.wait()

        await provider.appendLivechat([LivechatFixtures.message("a1", role: .agent, text: "agent")])
        await release.open()
        try await send.value

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.incoming.map(\.model) == [
            [.text(AttributedString("reply")), .text(AttributedString("agent"))]
        ])
    }

    @Test("a session that expires during a reply clears once the reply settles")
    func expiryDuringReplyWaits() async throws {
        let mock = MockChatService(.init(sendError: .transport(.http(.unhandled(status: 500, body: Data())))))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        let entered = AsyncGate()
        let release = AsyncGate()
        mock.sendHold = {
            await entered.open()
            await release.wait()
        }
        let send = Task { try await provider.send("hi") }
        await entered.wait()

        await provider.expireSession()
        await release.open()
        _ = try? await send.value

        var snapshots = provider.stream.makeAsyncIterator()
        let snapshot = await snapshots.next()
        #expect(snapshot?.user.isEmpty == true)
        #expect(snapshot?.incoming.isEmpty == true)
    }

    @Test("a livechat message already in history isn't appended again")
    func historyMessageIsNotReplayed() async throws {
        let history = Message(
            messageId: "a1",
            role: .agent,
            agent: nil,
            parts: [.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("agent")]))]))],
            createdAt: "2026-01-01T00:00:00Z"
        )
        let mock = MockChatService(.init(historyPages: [MessagePage(messages: [history], nextCursor: nil)]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        try await provider.loadOlder()

        await provider.appendLivechat([LivechatFixtures.message("a1", role: .agent, text: "agent")])

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.incoming.map(\.model) == [[.text(AttributedString("agent"))]])
    }

    @Test("visitor messages in a row share a turn, and a failed one pops only its bubble")
    func failedSecondSendPopsOneBubble() async throws {
        let provider = try await Self.providerAfterOneExchange(livechatSendError: .conflict)
        await provider.appendLivechat([LivechatFixtures.message("u1", role: .user, text: "one")])
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.livechatInactive(popped: "two")) {
            try await provider.sendLivechat("two")
        }

        #expect(await snapshots.next()?.user.map(\.model) == [[AttributedString("hi")], [AttributedString("one")]])
    }

    @Test("an AI send after an unanswered visitor message joins its turn and pops alone on failure")
    func aiSendAfterUnansweredMessage() async throws {
        let mock = MockChatService(.init(
            sendEvents: [Self.textPart("reply")],
            sendError: .transport(.http(.unhandled(status: 500, body: Data())))
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        await provider.appendLivechat([
            LivechatFixtures.message("u1", role: .user, text: "one", sequence: 1),
            LivechatFixtures.message("a1", role: .agent, text: "answer", sequence: 2),
            LivechatFixtures.message("u2", role: .user, text: "two", sequence: 3)
        ])
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: "three", body: nil)) {
            try await provider.send("three")
        }

        #expect(await snapshots.next()?.user.map(\.model) == [[AttributedString("one")], [AttributedString("two")]])
    }

    @Test("expireSession clears the conversation")
    func expireSessionClears() async {
        let provider: any ChatProviding = ChatProvider(service: MockChatService(), pageContext: { nil })
        await provider.appendLivechat([LivechatFixtures.message("u", role: .user, text: "hi")])
        var snapshots = provider.stream.makeAsyncIterator()

        await provider.expireSession()

        #expect(await snapshots.next()?.turns.isEmpty == true)
    }
}

private extension ChatProviderLivechatTests {

    /// A provider whose conversation is one AI exchange: "hi", then "reply".
    static func providerAfterOneExchange(
        livechatSendError: ChatServiceError? = nil
    ) async throws -> any ChatProviding {
        let mock = MockChatService(.init(sendEvents: [Self.textPart("reply")], livechatSendError: livechatSendError))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        try await provider.send("hi")
        return provider
    }

    static func textPart(_ text: String) -> StreamEvent {
        .part(.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text(text)]))])))
    }
}
