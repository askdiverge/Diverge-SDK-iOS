//
//  ChatProviderLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — livechat")
struct ChatProviderLivechatTests {

    @Test("AI send 409 pops both turns and surfaces .conflict")
    func sendConflictPopsEcho() async {
        let mock = MockChatService(.init(sendError: .conflict))
        let provider = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.conflict(popped: "hi")) {
            try await provider.send("hi")
        }

        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.isEmpty == true)
        #expect(snapshot?.lastSentUserTurnID == nil)
    }

    @Test("sendLivechat records the id so a later poll of the same id is a no-op")
    func sendLivechatDedupe() async throws {
        let stored = Self.livechatUser(id: "livechat_msg_1", text: "hi", sequence: 1)
        let mock = MockChatService(.init(livechatSendResponse: stored))
        let provider = ChatProvider(service: mock, pageContext: { nil })
        let stream = provider.stream
        let collector = Task {
            var last: ConversationSnapshot?
            for await snap in stream { last = snap }
            return last
        }
        try await provider.sendLivechat("hi")
        await provider.appendLivechat([stored])
        await provider.appendLivechat([Self.livechatAgent(id: "a1", text: "ok", sequence: 2)])
        try await Task.sleep(for: .milliseconds(20))
        collector.cancel()
        let last = await collector.value
        let userTurns = last?.turns.filter { if case .user = $0.model { return true }; return false } ?? []
        let agentTurns = last?.turns.filter { if case .agent = $0.model { return true }; return false } ?? []
        #expect(userTurns.count == 1)
        #expect(agentTurns.count == 1)
    }

    @Test("sendLivechat failure pops the echo")
    func sendLivechatFailurePopsEcho() async {
        let mock = MockChatService(.init(livechatSendError: .transport(.http(.unhandled(status: 500)))))
        let provider = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: nil)) {
            try await provider.sendLivechat("hi")
        }
        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.isEmpty == true)
        #expect(snapshot?.lastSentUserTurnID == nil)
    }

    @Test("sendLivechat 409 surfaces .livechatInactive and pops the echo")
    func sendLivechatConflict() async {
        let mock = MockChatService(.init(livechatSendError: .conflict))
        let provider = ChatProvider(service: mock, pageContext: { nil })
        await #expect(throws: ChatProvider.SendFailure.livechatInactive(popped: "hi")) {
            try await provider.sendLivechat("hi")
        }
    }

    @Test("appendLivechat maps user / agent / other roles")
    func roleMapping() async {
        let provider = ChatProvider(service: MockChatService(), pageContext: { nil })
        let stream = provider.stream
        let collector = Task {
            var last: ConversationSnapshot?
            for await snap in stream { last = snap }
            return last
        }
        await provider.appendLivechat([
            Self.livechatUser(id: "u", text: "hi", sequence: 1),
            Self.livechatAgent(id: "a", text: "hello", sequence: 2),
            LivechatMessage(
                messageId: "b",
                role: .assistant,
                parts: [.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("bot")]))]))],
                createdAt: "2025-01-01T00:00:00Z",
                sequenceNumber: 3
            ),
        ])
        try? await Task.sleep(for: .milliseconds(20))
        collector.cancel()
        let last = await collector.value
        #expect(last?.turns.count == 3)
        #expect(last?.turns[0].model.isUser == true)
        if case .agent(let agent, _) = last?.turns[1].model {
            #expect(agent.displayName == "Alice")
        } else {
            Issue.record("expected agent turn")
        }
        if case .bot = last?.turns[2].model {
            // ok
        } else {
            Issue.record("expected bot turn")
        }
    }

    @Test("a poll of the visitor's own message while send is in flight does not double-render")
    func midSendPollDoesNotDuplicate() async throws {
        let stored = Self.livechatUser(id: "livechat_msg_1", text: "hi", sequence: 1)
        let mock = MockChatService(.init(livechatSendResponse: stored))
        let provider = ChatProvider(service: mock, pageContext: { nil })
        let entered = AsyncGate()
        let release = AsyncGate()
        mock.livechatSendHold = {
            await entered.open()
            await release.wait()
        }
        let send = Task {
            try await provider.sendLivechat("hi")
        }
        await entered.wait()
        await provider.appendLivechat([stored])
        await release.open()
        try await send.value

        let stream = provider.stream
        // Publish a dummy agent so we can read the resulting turns.
        await provider.appendLivechat([Self.livechatAgent(id: "a1", text: "ok", sequence: 2)])
        var last: ConversationSnapshot?
        for await snap in stream {
            last = snap
            break
        }
        let userTurns = last?.turns.filter { $0.model.isUser } ?? []
        #expect(userTurns.count == 1)
    }

    @Test("expireSession clears the conversation")
    func expireSessionClears() async {
        let provider = ChatProvider(service: MockChatService(), pageContext: { nil })
        let stream = provider.stream
        let collector = Task {
            var last: ConversationSnapshot?
            for await snap in stream { last = snap }
            return last
        }
        await provider.appendLivechat([Self.livechatUser(id: "u", text: "hi", sequence: 1)])
        await provider.expireSession()
        try? await Task.sleep(for: .milliseconds(20))
        collector.cancel()
        let last = await collector.value
        #expect(last?.turns.isEmpty == true)
    }

    private static func livechatUser(id: String, text: String, sequence: Int64) -> LivechatMessage {
        LivechatMessage(
            messageId: id,
            role: .user,
            parts: [.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2025-01-01T00:00:00Z",
            sequenceNumber: sequence
        )
    }

    private static func livechatAgent(id: String, text: String, sequence: Int64) -> LivechatMessage {
        LivechatMessage(
            messageId: id,
            role: .agent,
            agent: LivechatAgent(agentId: "a", displayName: "Alice"),
            parts: [.richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2025-01-01T00:00:00Z",
            sequenceNumber: sequence
        )
    }
}
