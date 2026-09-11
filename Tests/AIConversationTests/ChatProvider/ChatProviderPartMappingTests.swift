//
//  ChatProviderPartMappingTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — part mapping")
struct ChatProviderPartMappingTests: ChatProviderTestHelpers {

    // MARK: - suggestions

    @Test("an authoritative suggestions part maps to suggestion cards")
    func suggestionsPartMaps() async throws {
        let cards = [self.suggestionCard(id: "s1", title: "Outfit 1", prompt: "Show outfit 1")]
        let mock = MockChatService(.init(sendEvents: [self.suggestionsPart(cards, partId: "sug")]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.suggestions(cards)]])
    }

    @Test("suggestion deltas assemble a preview that the authoritative part replaces")
    func suggestionDeltasMatchAuthoritative() async throws {
        let cardA = self.suggestionCard(id: "s1", title: "Outfit 1", prompt: "Show outfit 1")
        let cardB = self.suggestionCard(id: "s2", title: "Outfit 2", prompt: "Show outfit 2", description: "See the look")
        let events = self.suggestionDeltas([cardA, cardB], partId: "sug")
            + [self.suggestionsPart([cardA, cardB], partId: "sug")]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.suggestions([cardA, cardB])]])
    }

    @Test("an empty suggestions part renders nothing")
    func emptySuggestionsPartSkipped() async throws {
        let mock = MockChatService(.init(sendEvents: [
            self.suggestionsPart([], partId: "sug"),
            self.textPart("after")
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.text(AttributedString("after"))]])
    }

    @Test("history suggestions parts map to suggestion cards")
    func historySuggestionsPrepend() async throws {
        let cards = [self.suggestionCard(id: "s1", title: "Outfit 1", prompt: "Show outfit 1")]
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.suggestions(Suggestions(partId: "sug", suggestions: cards))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.suggestions(cards)]])
    }

    @Test("an authoritative quick_replies part maps to chips")
    func quickRepliesPartMaps() async throws {
        let mock = MockChatService(.init(sendEvents: [
            .part(.quickReplies(QuickReplies(partId: "qr", replies: ["Track order", "Return"])))
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.quickReplies(["Track order", "Return"])]])
    }

    // MARK: - request_image_upload

    @Test("an authoritative request_image_upload part maps to the upload prompt")
    func requestImageUploadPartMaps() async throws {
        let marker = self.requestImageUpload()
        let mock = MockChatService(.init(sendEvents: [self.requestImageUploadPart(marker)]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.requestImageUpload(marker)]])
    }

    @Test("done reconciles a request_image_upload that never streamed")
    func doneReconcilesRequestImageUpload() async throws {
        let marker = self.requestImageUpload()
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))])),
                .requestImageUpload(marker)
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[
            .text(AttributedString("hello")),
            .requestImageUpload(marker)
        ]])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("history request_image_upload parts map to the upload prompt")
    func historyRequestImageUploadPrepend() async throws {
        let marker = self.requestImageUpload()
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.requestImageUpload(marker)],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.requestImageUpload(marker)]])
    }

    @Test("done order wins when the marker is persisted ahead of the text that streamed")
    func doneReordersRequestImageUpload() async throws {
        let marker = self.requestImageUpload()
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [
                .requestImageUpload(marker),
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))]))
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[
            .requestImageUpload(marker),
            .text(AttributedString("hello"))
        ]])
    }

    // MARK: - request_image_upload with attachments disabled by the host

    @Test("with prompts disabled a marker-only history message produces no turn")
    func historyMarkerOnlyDroppedWhenPromptsDisabled() async throws {
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.requestImageUpload(self.requestImageUpload())],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("b0"), message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(
            service: mock,
            pageContext: { nil },
            acceptsImageUploadPrompts: false
        )
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.map { Self.label($0.model) } == ["b0"], "no empty row for the marker")
    }

    @Test("with prompts disabled a marker beside text is dropped and the text survives")
    func donePartMarkerDroppedWhenPromptsDisabled() async throws {
        let marker = self.requestImageUpload()
        let events = self.textDeltas("hello")
            + [self.textPart("hello"), self.requestImageUploadPart(marker)]
            + [self.doneMessage(parts: [
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))])),
                .requestImageUpload(marker)
            ])]
        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(
            service: mock,
            pageContext: { nil },
            acceptsImageUploadPrompts: false
        )
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.text(AttributedString("hello"))]])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("with prompts disabled a marker-only live reply leaves no bot turn")
    func liveMarkerOnlyDroppedWhenPromptsDisabled() async throws {
        let marker = self.requestImageUpload()
        let events = [self.requestImageUploadPart(marker)]
            + [self.doneMessage(parts: [.requestImageUpload(marker)])]
        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(
            service: mock,
            pageContext: { nil },
            acceptsImageUploadPrompts: false
        )
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.userTurns.count == 1, "the echo stays")
        #expect(snapshot?.botTurns == [], "nothing rendered, so the placeholder path removes the turn")
    }

    // MARK: - unknown markers (forms / livechat)

    @Test("an authoritative show_contact_form part renders nothing")
    func contactFormPartIsSkipped() async throws {
        let mock = MockChatService(.init(sendEvents: [
            .part(.unknown)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [])
    }

    @Test("done with only a show_support_ticket leaves no bot turn")
    func doneWithOnlySupportTicketIsSkipped() async throws {
        let events = [
            self.doneMessage(parts: [.unknown])
        ]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("history show_form parts are skipped")
    func historyCustomFormIsSkipped() async throws {
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.unknown],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [])
    }
}
