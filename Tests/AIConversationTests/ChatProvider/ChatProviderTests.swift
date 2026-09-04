//
//  ChatProviderTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — session orchestration")
struct ChatProviderTests {

    // MARK: - send / delta assembly

    @Test("deltas assemble the in-flight reply preview")
    func deltasAssemblePreview() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("hel")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.user.map(\.model) == [[AttributedString("hi")]])
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("hel"))]])
    }

    @Test("the authoritative part replaces the delta preview")
    func partReplacesPreview() async throws {
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("hel")
            + [self.textPart("hello")]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("hello"))]])
    }

    @Test("multiple parts expand into adjacent bubbles within one turn")
    func multiPartExpands() async throws {
        let events = self.textDeltas("a", partId: "p0")
        + [self.textPart("A", partId: "p0")]
        + self.textDeltas("b", partId: "p1")
        + [self.textPart("B", partId: "p1")]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("A")), .text(AttributedString("B"))]])
    }

    // MARK: - send errors

    @Test("session expiry clears the conversation and surfaces .sessionExpired")
    func sessionExpiredClears() async {
        let mock = MockChatService(.init(sendError: .sessionExpired))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.sessionExpired) {
            try await provider.send("hi")
        }

        let snapshot = await snapshots.next()
        #expect(snapshot?.user == [])
        #expect(snapshot?.incoming == [])
    }

    @Test("stream failure discards the in-flight turn and surfaces retry with the server message")
    func streamFailureSurfacesRetry() async {
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("hel"),
            sendError: .stream(.init(code: .generationFailed, message: "boom", retryable: true))
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: "boom")) {
            try await provider.send("hi")
        }

        let snapshot = await snapshots.next()
        #expect(snapshot?.user == [])
        #expect(snapshot?.incoming == [])
    }

    // MARK: - pagination

    @Test("loadOlder fetches a page and prepends it")
    func loadOlderPrepends() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("a")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("a"))]])
        #expect(snapshot?.user == [])
    }

    @Test("loadOlder stops fetching once the cursor is exhausted")
    func loadOlderStopsWhenExhausted() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        try await provider.loadOlder()
        try await provider.loadOlder()

        #expect(mock.historyCallCount == 1)
    }

    // MARK: - reset / delete

    @Test("reset rotates the session, clears, and reloads history")
    func resetRotatesClearsReloads() async throws {
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("reply"),
            historyPages: [MessagePage(messages: [self.assistantMessage("hist")], nextCursor: nil)]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        try await provider.reset()

        let snapshot = await snapshots.next()
        #expect(mock.resetCallCount == 1)
        #expect(snapshot?.user == [])
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("hist"))]])
    }

    @Test("a failed reset throws before clearing or reloading")
    func resetFailureLeavesConversationIntact() async throws {
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("reply"),
            resetError: .provider(TestError())
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        try await provider.send("hi")

        await #expect(throws: (any Error).self) {
            try await provider.reset()
        }
        #expect(mock.resetCallCount == 1)
        #expect(mock.historyCallCount == 0) // bailed before the reload
    }

    @Test("delete wipes the conversation")
    func deleteClears() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("reply")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        try await provider.delete()

        let snapshot = await snapshots.next()
        #expect(mock.deleteCallCount == 1)
        #expect(snapshot?.user == [])
        #expect(snapshot?.incoming == [])
    }

    @Test("a failed delete throws and leaves the conversation intact")
    func deleteFailureLeavesConversationIntact() async {
        let mock = MockChatService(.init(deleteError: .provider(TestError())))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        await #expect(throws: (any Error).self) {
            try await provider.delete()
        }
        #expect(mock.deleteCallCount == 1)
    }

    // MARK: - welcome

    @Test("the welcome message is seeded as the first incoming bubble")
    func welcomeSeeded() async throws {
        let mock = MockChatService()
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("Hi"))]])
    }

    @Test("the welcome survives reset — re-seeded after clearing")
    func welcomeSurvivesReset() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("reply")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        try await provider.reset()

        let snapshot = await snapshots.next()
        #expect(snapshot?.incoming.map(\.model) == [[.text(AttributedString("Hi"))]])
        #expect(snapshot?.user == [])
    }
}

// MARK: - Fixtures

private extension ChatProviderTests {

    /// The rich_text delta sequence that streams a single paragraph of `text`.
    func textDeltas(_ text: String, partId: String = "p") -> [StreamEvent] {
        [
            .delta(partId: partId, .richText(.start)),
            .delta(partId: partId, .richText(.startBlock(index: 0, type: .paragraph))),
            .delta(partId: partId, .richText(.appendText(index: 0, text: text)))
        ]
    }

    /// The authoritative `part` for a single paragraph of `text`.
    func textPart(_ text: String, partId: String = "p") -> StreamEvent {
        .part(.richText(RichText(partId: partId, blocks: [.paragraph(.init(spans: [.text(text)]))])))
    }

    /// An assistant history message carrying a single paragraph of `text`.
    func assistantMessage(_ text: String) -> Message {
        Message(
            messageId: "m",
            role: .assistant,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }
}

private struct TestError: Error {}
