//
//  ChatProviderSendTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — send and streaming")
struct ChatProviderSendTests: ChatProviderTestHelpers {

    // MARK: - send / delta assembly

    @Test("deltas assemble the in-flight reply preview")
    func deltasAssemblePreview() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("hel")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.userTurns == [[.text(AttributedString("hi"))]])
        #expect(snapshot?.botTurns == [[.text(AttributedString("hel"))]])
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
        #expect(snapshot?.botTurns == [[.text(AttributedString("hello"))]])
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
        #expect(snapshot?.botTurns == [[.text(AttributedString("A")), .text(AttributedString("B"))]])
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
        #expect(snapshot?.userTurns == [])
        #expect(snapshot?.botTurns == [])
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
        #expect(snapshot?.userTurns == [])
        #expect(snapshot?.botTurns == [])
        #expect(snapshot?.lastSentUserTurnID == nil)
    }

    @Test("failed send clears lastSentUserTurnID when the echo is popped")
    func failedSendClearsLastSentUserTurnID() async {
        let mock = MockChatService(.init(sendError: .transport(.http(.unhandled(status: 500)))))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        await #expect(throws: (any Error).self) {
            try await provider.send("hi")
        }

        let snapshot = await snapshots.next()
        #expect(snapshot?.lastSentUserTurnID == nil)
        #expect(snapshot?.userTurns == [])
    }

    // MARK: - a live send over ordered history

    @Test("a send after a non-alternating page appends the echo and the reply at the end, in order")
    func sendAppendsAfterOrderedHistory() async throws {
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("reply"),
            historyPages: [
                MessagePage(
                    messages: [self.assistantMessage("b1"), self.userMessage("u1"), self.assistantMessage("b0")],
                    nextCursor: nil
                )
            ]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        _ = await snapshots.next()
        try await provider.send("hi")
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["b0", "u1", "b1", "hi", "reply"])
    }

    @Test("a page landing mid-stream leaves the deltas in the streaming turn, not in a history bot turn")
    func prependMidStreamKeepsDeltasInStreamingTurn() async throws {
        let gate = AsyncGate()
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("hel"),
            sendHold: { await gate.wait() },
            sendEventsAfterHold: [.delta(partId: "p", .richText(.appendText(index: 0, text: "lo")))],
            historyPages: [
                MessagePage(messages: [self.assistantMessage("b1"), self.userMessage("u0")], nextCursor: nil)
            ]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        let send = Task { try await provider.send("hi") }
        await self.awaitPreview("hel", from: &snapshots)

        // The actor is free while the send awaits its next event — the page lands above the exchange.
        #expect(try await provider.loadOlder())
        await gate.open()
        try await send.value
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["u0", "b1", "hi", "hello"])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("a stream failure after a mid-stream page removes exactly the echo and the placeholder")
    func streamFailureAfterPrependPopsOnlyTheEcho() async throws {
        let gate = AsyncGate()
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("hel"),
            sendHold: { await gate.wait() },
            sendError: .stream(.init(code: .generationFailed, message: "boom", retryable: true)),
            historyPages: [
                MessagePage(messages: [self.assistantMessage("b1"), self.userMessage("u0")], nextCursor: nil)
            ]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        let send = Task { try await provider.send("hi") }
        await self.awaitPreview("hel", from: &snapshots)

        #expect(try await provider.loadOlder())
        await gate.open()
        await #expect(throws: ChatProvider.SendFailure.retry(popped: "hi", body: "boom")) {
            try await send.value
        }
        let snapshot = await snapshots.next()

        // History — including its own user turn — is intact; only the send's two turns are gone.
        #expect(snapshot?.turns.map { Self.label($0.model) } == ["u0", "b1"])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("send sets lastSentUserTurnID to the optimistic echo")
    func sendSetsLastSentUserTurnID() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("reply")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        let snapshot = await snapshots.next()

        #expect(snapshot?.lastSentUserTurnID != nil)
        #expect(snapshot?.lastSentUserTurnID == snapshot?.lastUserTurnID)
    }

    // MARK: - user attachments

    @Test("send with an image attachment echoes text and image in one user turn")
    func sendEchoesImageAttachment() async throws {
        let attachment = OutgoingAttachment(
            kind: .image,
            data: "aGVsbG8=",
            mime: "image/jpeg",
            filename: "receipt.jpg"
        )
        let mock = MockChatService(.init(sendEvents: self.textDeltas("ok") + [self.textPart("ok")]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("see this", attachments: [attachment])

        let snapshot = await snapshots.next()
        let url = attachment.dataURL!
        #expect(snapshot?.userTurns == [[
            .text(AttributedString("see this")),
            .image(MessageImage(url: url, mimeType: "image/jpeg", caption: "receipt.jpg"))
        ]])
        #expect(mock.lastSendText == "see this")
        #expect(mock.lastSendAttachments == [attachment])
    }

    @Test("history user image parts map to UserContent.image")
    func historyUserImagePrepend() async throws {
        let image = self.messageImage(
            url: "data:image/png;base64,aGVsbG8=",
            caption: "mine.png"
        )
        let message = Message(
            messageId: "m",
            role: .user,
            parts: [.image(image)],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.userTurns == [[.image(image)]])
        #expect(snapshot?.botTurns == [])
    }

    @Test("discardInFlight after an attachment send still returns the text")
    func discardInFlightReturnsTextWithAttachment() async throws {
        let attachment = OutgoingAttachment(
            kind: .image,
            data: "aGVsbG8=",
            mime: "image/jpeg",
            filename: "a.jpg"
        )
        let mock = MockChatService(.init(sendError: .transport(.http(.unhandled(status: 500)))))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        do {
            try await provider.send("caption", attachments: [attachment])
            Issue.record("expected retry failure")
        } catch ChatProvider.SendFailure.retry(popped: let popped, body: _) {
            #expect(popped == "caption")
        }
    }
}
