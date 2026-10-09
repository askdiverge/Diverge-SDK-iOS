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

    @Test("a timed-out livechat send is posted again under the same operation id and stays on screen")
    func timedOutSendIsRetriedOnce() async throws {
        let stored = LivechatFixtures.message("u1", role: .user, text: "hi **there**\n\n- one")
        let mock = MockChatService(.init(
            livechatSendResponse: stored,
            livechatSendFailingCalls: [0: .transport(.connection(URLError(.timedOut)))]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        try await provider.sendLivechat("hi **there**\n\n- one")
        await provider.appendLivechat([stored])

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.user.map(\.model) == [[AttributedString("hi **there**\n\n- one")]])
        #expect(mock.livechatSendOperationIds.count == 2)
        #expect(Set(mock.livechatSendOperationIds).count == 1)
    }

    @Test("a livechat send whose retry fails too is popped, and the next send gets a new operation id")
    func failedRetryIsPopped() async {
        let mock = MockChatService(.init(livechatSendError: .transport(.connection(URLError(.timedOut)))))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: nil)) {
            try await provider.sendLivechat("hi")
        }
        #expect(await snapshots.next()?.user.isEmpty == true)
        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: nil)) {
            try await provider.sendLivechat("hi")
        }

        #expect(mock.livechatSendOperationIds.count == 4)
        #expect(Set(mock.livechatSendOperationIds).count == 2)
    }

    @Test("a 401 on the retried livechat send ends the session")
    func expiryOnRetry() async {
        let mock = MockChatService(.init(livechatSendFailingCalls: [
            0: .transport(.connection(URLError(.timedOut))),
            1: .sessionExpired
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.sessionExpired) {
            try await provider.sendLivechat("hi")
        }

        #expect(await snapshots.next()?.turns.isEmpty == true)
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

    @Test("the log's copies of messages history shows under other ids aren't appended again")
    func historyCopiesAreSkipped() async throws {
        let mock = MockChatService(.init(historyPages: [MessagePage(
            messages: [
                Self.historyMessage("conv_7_1", role: .agent, text: "agent", createdAt: "2026-01-01T10:00:00.123456+00:00"),
                Self.historyMessage("conv_7_0", role: .user, text: "hi", createdAt: "2026-01-01T09:59:00.5Z")
            ],
            nextCursor: nil
        )]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        try await provider.loadOlder()

        await provider.appendLivechat([
            LivechatFixtures.message("9f1c", role: .user, text: "hi", sequence: 1, createdAt: "2026-01-01T09:59:00.500Z"),
            LivechatFixtures.message("9f1d", role: .agent, text: "agent", sequence: 2, createdAt: "2026-01-01T10:00:00.123Z"),
            LivechatFixtures.message("9f1e", role: .agent, text: "later", sequence: 3, createdAt: "2026-01-01T10:00:00.124Z")
        ])

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.turns.map(\.model) == [
            .user([AttributedString("hi")]),
            .bot([.text(AttributedString("agent")), .text(AttributedString("later"))])
        ])
    }

    @Test("an agent message that opens an empty conversation leads it, and the visitor's reply follows")
    func agentOpensConversation() async throws {
        let mock = MockChatService(.init(sendEvents: [Self.textPart("reply")]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        await provider.appendLivechat([LivechatFixtures.message("a1", role: .agent, text: "hello")])
        try await provider.send("hi")
        try await provider.send("again")

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.turns.map(\.model) == [
            .bot([.text(AttributedString("hello"))]),
            .user([AttributedString("hi")]),
            .bot([.text(AttributedString("reply"))]),
            .user([AttributedString("again")]),
            .bot([.text(AttributedString("reply"))])
        ])
    }

    @Test("history messages in a row from one side share a turn, across pages and in the order sent")
    func historyRunsShareTurns() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(
                messages: [
                    Self.historyMessage("m4", role: .user, text: "thanks"),
                    Self.historyMessage("m3", role: .agent, text: "two")
                ],
                nextCursor: "older"
            ),
            MessagePage(
                messages: [
                    Self.historyMessage("m2", role: .agent, text: "one"),
                    Self.historyMessage("m1", role: .user, text: "hi")
                ],
                nextCursor: nil
            )
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        try await provider.loadOlder()
        try await provider.loadOlder()

        var snapshots = provider.stream.makeAsyncIterator()
        #expect(await snapshots.next()?.turns.map(\.model) == [
            .user([AttributedString("hi")]),
            .bot([.text(AttributedString("one")), .text(AttributedString("two"))]),
            .user([AttributedString("thanks")])
        ])
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

    static func historyMessage(
        _ id: String,
        role: Message.Role,
        text: String,
        createdAt: String = "2026-01-01T00:00:00Z"
    ) -> Message {
        Message(
            messageId: id,
            role: role,
            agent: nil,
            parts: [.richText(RichText(partId: "p_\(id)", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: createdAt
        )
    }

    static func textPart(_ text: String) -> StreamEvent {
        .part(.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text(text)]))])))
    }
}
