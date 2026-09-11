//
//  ChatProviderReconcileTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — done reconciliation and media history")
struct ChatProviderReconcileTests: ChatProviderTestHelpers {

    // MARK: - done reconciliation

    @Test("done reconciles streamed text with an image part that never streamed")
    func doneReconcilesImage() async throws {
        let image = self.messageImage()
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))])),
                .image(image)
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[
            .text(AttributedString("hello")),
            .image(image)
        ]])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("done with no renderable parts leaves streamed content intact")
    func doneEmptyLeavesStreamed() async throws {
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [.unknown])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.text(AttributedString("hello"))]])
    }

    @Test("done order wins over streamed order — persisted message is the source of truth")
    func doneOrderWins() async throws {
        // Streamed: text first, then suggestions. Persisted: suggestions first, then text.
        let cards = [self.suggestionCard(id: "s1", title: "Outfit", prompt: "Show outfit")]
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.suggestionsPart(cards)]
            + [self.doneMessage(parts: [
                .suggestions(Suggestions(partId: "sug", suggestions: cards)),
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))]))
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[
            .suggestions(cards),
            .text(AttributedString("hello"))
        ]])
    }

    @Test("done with an unrenderable attachment beside text keeps the text and drops the attachment")
    func doneMalformedAttachmentKeepsText() async throws {
        // A malformed image / file part decodes to `.unknown` (see UnknownFallbackTests) rather
        // than throwing, so `done` still lands and the streamed reply is not discarded.
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))])),
                .unknown
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.text(AttributedString("hello"))]])
        #expect(snapshot?.userTurns == [[.text(AttributedString("hi"))]])
    }

    @Test("absent done still drops a never-overwritten placeholder")
    func absentDoneDropsPlaceholder() async throws {
        // No part and no done — the thinking placeholder is all that remains.
        let mock = MockChatService(.init(sendEvents: []))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [])
        #expect(snapshot?.userTurns == [[.text(AttributedString("hi"))]])
    }

    // MARK: - image / file history

    @Test("history image parts map to image responses")
    func historyImagePrepend() async throws {
        let image = self.messageImage()
        let message = Message(
            messageId: "m",
            role: .assistant,
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
        #expect(snapshot?.botTurns == [[.image(image)]])
    }

    @Test("history file parts map to file responses")
    func historyFilePrepend() async throws {
        let file = self.messageFile()
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.file(file)],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.file(file)]])
    }
}
