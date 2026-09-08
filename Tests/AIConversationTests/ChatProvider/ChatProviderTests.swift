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
        #expect(snapshot?.botTurns == [[.text(AttributedString("a"))]])
        #expect(snapshot?.userTurns == [])
        #expect(snapshot?.canLoadOlder == false)
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

    @Test("canLoadOlder stays true while a nextCursor remains")
    func canLoadOlderWhileCursorRemains() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("page1")], nextCursor: "cursor_2"),
            MessagePage(messages: [self.assistantMessage("page2")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let first = await snapshots.next()
        #expect(first?.canLoadOlder == true)
        #expect(first?.botTurns == [[.text(AttributedString("page1"))]])

        try await provider.loadOlder()
        let second = await snapshots.next()
        #expect(second?.canLoadOlder == false)
        #expect(second?.botTurns == [
            [.text(AttributedString("page2"))],
            [.text(AttributedString("page1"))]
        ])
    }

    @Test("loadOlder past exhaustion makes no second network call and reports nothing prepended")
    func loadOlderPastExhaustionNoFetch() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("only")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        let prepended = try await provider.loadOlder()
        let first = await snapshots.next()
        #expect(prepended)
        #expect(first?.canLoadOlder == false)
        #expect(first?.botTurns == [[.text(AttributedString("only"))]])

        // Exhausted — Paginator.Failure.exhausted is swallowed, nothing is fetched.
        let again = try await provider.loadOlder()
        #expect(!again)
        #expect(mock.historyCallCount == 1)
    }

    @Test("an empty page with no cursor reports nothing prepended")
    func emptyPageReportsNoPrepend() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        #expect(try await provider.loadOlder() == false)
    }

    @Test("a failed load keeps the cursor and canLoadOlder — the retry fetches the same page")
    func failedLoadKeepsCursorForRetry() async throws {
        let mock = MockChatService(.init(
            historyPages: [
                MessagePage(messages: [self.assistantMessage("page1")], nextCursor: "cursor_2"),
                MessagePage(messages: [self.assistantMessage("page2")], nextCursor: nil)
            ],
            historyFailingCalls: [1: .transport(.connection(URLError(.notConnectedToInternet)))]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let first = await snapshots.next()
        #expect(first?.canLoadOlder == true)

        // Transient failure: rethrown, no publish, cursor retained.
        await #expect(throws: ChatServiceError.self) { try await provider.loadOlder() }

        // Retry asks for the same cursor and lands the missed page.
        let prepended = try await provider.loadOlder()
        let second = await snapshots.next()
        #expect(prepended)
        #expect(mock.historyCursors == [nil, "cursor_2", "cursor_2"])
        #expect(second?.canLoadOlder == false)
        #expect(second?.botTurns == [
            [.text(AttributedString("page2"))],
            [.text(AttributedString("page1"))]
        ])
    }

    @Test("session expiry during loadOlder clears the conversation and leaves nothing to anchor to")
    func sessionExpiryDuringLoadOlderClears() async throws {
        let mock = MockChatService(.init(
            historyPages: [
                MessagePage(messages: [self.assistantMessage("page1")], nextCursor: "cursor_2")
            ],
            historyFailingCalls: [1: .sessionExpired]
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        _ = await snapshots.next()

        do {
            try await provider.loadOlder()
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        }

        // Fresh paginator so canLoadOlder reads true, but turns are empty — the UI's
        // "nothing to anchor to" guard is what keeps it from spinning on an ended session.
        let cleared = await snapshots.next()
        #expect(cleared?.turns.isEmpty == true)
        #expect(cleared?.canLoadOlder == true)
    }

    @Test("the welcome is pinned above history only once the last page has landed")
    func welcomeInsertedOnExhaustingPage() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("page1")], nextCursor: "cursor_2"),
            MessagePage(messages: [self.assistantMessage("page2")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let first = await snapshots.next()
        #expect(first?.botTurns == [[.text(AttributedString("page1"))]])
        // Welcome is only pinned once history is exhausted — not on a mid-cursor page.
        #expect(first?.turns.first.map { Self.label($0.model) } == "page1")

        try await provider.loadOlder()
        let second = await snapshots.next()
        #expect(second?.botTurns == [
            [.text(AttributedString("Hi"))],
            [.text(AttributedString("page2"))],
            [.text(AttributedString("page1"))]
        ])
        #expect(second?.turns.first.map { Self.label($0.model) } == "Hi")
    }

    @Test("an older page that starts with a bot turn keeps chronological order after a user-led first page")
    func botLedOlderPageStaysChronological() async throws {
        let mock = MockChatService(.init(historyPages: [
            // newest first on the wire: b1 then u1 → chronological u1, b1
            MessagePage(
                messages: [self.assistantMessage("b1"), self.userMessage("u1")],
                nextCursor: "cursor_2"
            ),
            MessagePage(messages: [self.assistantMessage("b0")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        _ = await snapshots.next()
        try await provider.loadOlder()
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["b0", "u1", "b1"])
    }

    @Test("two consecutive bot messages on one page stay consecutive")
    func consecutiveBotMessagesStayOrdered() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(
                messages: [
                    self.assistantMessage("b2"),
                    self.assistantMessage("b1"),
                    self.userMessage("u0")
                ],
                nextCursor: nil
            )
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["u0", "b1", "b2"])
    }

    @Test("two consecutive user messages before a reply stay consecutive")
    func consecutiveUserMessagesStayOrdered() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(
                messages: [
                    self.assistantMessage("b2"),
                    self.userMessage("u1"),
                    self.userMessage("u0")
                ],
                nextCursor: nil
            )
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["u0", "u1", "b2"])
    }

    @Test("a system note mid-page keeps its place between user and assistant turns")
    func systemNoteStaysInPlace() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(
                messages: [
                    self.assistantMessage("b2"),
                    self.systemMessage("note"),
                    self.userMessage("u0")
                ],
                nextCursor: nil
            )
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["u0", "note", "b2"])
        #expect(snapshot?.lastSentUserTurnID == nil)
    }

    @Test("prepending a user turn on a bot-led page does not arm lastSentUserTurnID")
    func prependUserDoesNotArmSendExchange() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(
                messages: [self.assistantMessage("b0"), self.userMessage("u0")],
                nextCursor: nil
            )
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let snapshot = await snapshots.next()

        #expect(snapshot?.lastUserTurnID != nil)
        #expect(snapshot?.lastSentUserTurnID == nil)
    }

    @Test("a page whose parts all render to nothing reports nothing prepended and leaves the snapshot alone")
    func unrenderablePageReportsNoPrepend() async throws {
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [self.assistantMessage("page1")], nextCursor: "cursor_2"),
            MessagePage(messages: [self.unknownPartMessage(), self.unknownPartMessage()], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()
        let first = await snapshots.next()

        let prepended = try await provider.loadOlder()
        let second = await snapshots.next()

        #expect(!prepended)
        #expect(second?.turns == first?.turns)
        #expect(second?.canLoadOlder == false)
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
        #expect(snapshot?.userTurns == [])
        #expect(snapshot?.botTurns == [[.text(AttributedString("hist"))]])
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
        #expect(snapshot?.userTurns == [])
        #expect(snapshot?.botTurns == [])
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

    @Test("export returns JSON without clearing the conversation")
    func exportKeepsConversation() async throws {
        let payload = Data(#"{"generated_at":"2026-01-01T00:00:00Z","chatbot_id":"bot","visitor_id":"v"}"#.utf8)
        let mock = MockChatService(.init(
            sendEvents: self.textDeltas("reply"),
            exportData: payload
        ))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        let before = await snapshots.next()
        let data = try await provider.exportMyData()

        #expect(mock.exportCallCount == 1)
        #expect(data == payload)
        #expect(before?.userTurns.isEmpty == false)
        // No publish on export — stream stays quiet; turns still present on a later send/load.
        try await provider.send("again")
        let after = await snapshots.next()
        #expect(after?.userTurns.count ?? 0 >= 2)
    }

    @Test("export 401 surfaces as sessionExpired without clearing")
    func exportExpiredSurfaces() async {
        let mock = MockChatService(.init(exportError: .sessionExpired))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })

        do {
            _ = try await provider.exportMyData()
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            #expect(mock.exportCallCount == 1)
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }
    }

    // MARK: - welcome

    @Test("the welcome message is seeded as the first turn")
    func welcomeSeeded() async throws {
        let mock = MockChatService()
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.first.map { Self.label($0.model) } == "Hi")
        #expect(snapshot?.botTurns == [[.text(AttributedString("Hi"))]])
    }

    @Test("the welcome is pinned above a bot-led exhausting page")
    func welcomeAboveBotLedPage() async throws {
        let mock = MockChatService(.init(historyPages: [
            // newest first on the wire: u1 then b0 → chronological b0, u1
            MessagePage(messages: [self.userMessage("u1"), self.assistantMessage("b0")], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        #expect(try await provider.loadOlder())
        let snapshot = await snapshots.next()

        #expect(snapshot?.turns.map { Self.label($0.model) } == ["Hi", "b0", "u1"])
    }

    @Test("an exhausting empty page still lands the welcome and reports a prepend")
    func welcomeOnEmptyExhaustingPageReportsPrepend() async throws {
        let mock = MockChatService(.init(historyPages: [MessagePage(messages: [], nextCursor: nil)]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        // The view anchors on `turns.first` changing — the welcome is that change.
        #expect(try await provider.loadOlder())
        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.map { Self.label($0.model) } == ["Hi"])
    }

    @Test("the welcome survives reset — re-seeded after clearing")
    func welcomeSurvivesReset() async throws {
        let mock = MockChatService(.init(sendEvents: self.textDeltas("reply")))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil }, welcomeMessage: "Hi")
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")
        try await provider.reset()

        let snapshot = await snapshots.next()
        #expect(snapshot?.turns.first.map { Self.label($0.model) } == "Hi")
        #expect(snapshot?.botTurns == [[.text(AttributedString("Hi"))]])
        #expect(snapshot?.userTurns == [])
    }

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

    // MARK: - form markers

    @Test("an authoritative show_contact_form part maps to a ConversationForm")
    func contactFormPartMaps() async throws {
        let form = self.contactForm()
        let mock = MockChatService(.init(sendEvents: [self.formPart(.showContactForm(
            ShowContactForm(partId: form.partId, fields: form.fields)
        ))]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.form(form)]])
    }

    @Test("done reconciles a show_support_ticket that never streamed")
    func doneReconcilesSupportTicket() async throws {
        let form = self.ticketForm()
        let events = self.textDeltas("hello")
            + [self.textPart("hello")]
            + [self.doneMessage(parts: [
                .richText(RichText(partId: "p", blocks: [.paragraph(.init(spans: [.text("hello")]))])),
                .showSupportTicket(ShowSupportTicket(
                    partId: form.partId,
                    fields: form.fields,
                    attachmentsAccepted: true,
                    maxAttachmentSizeBytes: 2_097_152
                ))
            ])]

        let mock = MockChatService(.init(sendEvents: events))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.send("hi")

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[
            .text(AttributedString("hello")),
            .form(form)
        ]])
        #expect(snapshot?.streamingTurnID == nil)
    }

    @Test("history show_form parts map to a ConversationForm")
    func historyCustomFormPrepend() async throws {
        let form = self.customForm()
        let message = Message(
            messageId: "m",
            role: .assistant,
            parts: [.showForm(ShowForm(
                partId: form.partId,
                formId: "salesLead",
                name: "Sales lead",
                confirmationText: "Thanks!",
                fields: form.fields,
                minFilledFields: 1
            ))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
        let mock = MockChatService(.init(historyPages: [
            MessagePage(messages: [message], nextCursor: nil)
        ]))
        let provider: any ChatProviding = ChatProvider(service: mock, pageContext: { nil })
        var snapshots = provider.stream.makeAsyncIterator()

        try await provider.loadOlder()

        let snapshot = await snapshots.next()
        #expect(snapshot?.botTurns == [[.form(form)]])
    }

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

// MARK: - Snapshot accessors

private extension ConversationSnapshot {
    /// User-turn contents in chronological order — content-only assertions.
    var userTurns: [[UserContent]] {
        self.turns.compactMap {
            if case .user(let contents) = $0.model { return contents }
            return nil
        }
    }

    /// Bot-turn responses in chronological order — content-only assertions.
    var botTurns: [[ChatResponse]] {
        self.turns.compactMap {
            if case .bot(let responses) = $0.model { return responses }
            return nil
        }
    }
}

// MARK: - Fixtures

private extension ChatProviderTests {

    /// Short label for a turn's first text bubble — used by ordering assertions.
    static func label(_ turn: ConversationSnapshot.Turn) -> String {
        switch turn {
        case .bot(let responses), .agent(_, let responses), .system(let responses):
            if case .text(let text)? = responses.first { return String(text.characters) }
        case .user(let contents):
            if case .text(let text)? = contents.first { return String(text.characters) }
        case .note:
            return "note"
        }
        return "?"
    }

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

    /// A user history message carrying a single paragraph of `text`.
    func userMessage(_ text: String) -> Message {
        Message(
            messageId: "u",
            role: .user,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }

    /// A system history message carrying a single paragraph of `text` — folds into a bot turn.
    func systemMessage(_ text: String) -> Message {
        Message(
            messageId: "sys",
            role: .system,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }

    /// An assistant history message whose only part is one this client cannot render.
    func unknownPartMessage() -> Message {
        Message(messageId: "x", role: .assistant, parts: [.unknown], createdAt: "2026-01-01T00:00:00.000Z")
    }

    /// Drains snapshots until the newest turn's first bubble reads `text` — the point at which the
    /// provider has consumed every event published so far and is suspended on the next one.
    func awaitPreview(_ text: String, from snapshots: inout AsyncStream<ConversationSnapshot>.Iterator) async {
        while let snapshot = await snapshots.next() {
            if snapshot.turns.last.map({ Self.label($0.model) }) == text { return }
        }
        Issue.record("stream ended before the preview \"\(text)\" was published")
    }

    /// A suggestion card fixture.
    func suggestionCard(
        id: String,
        title: String,
        prompt: String,
        description: String? = nil
    ) -> Suggestions.Card {
        Suggestions.Card(
            id: id,
            title: title,
            description: description,
            imageUrl: URL(string: "https://cdn.example.com/\(id).jpg")!,
            promptText: prompt
        )
    }

    /// The suggestions delta sequence that streams the given cards.
    func suggestionDeltas(_ cards: [Suggestions.Card], partId: String = "sug") -> [StreamEvent] {
        [.delta(partId: partId, .suggestions(.start))]
            + cards.map { .delta(partId: partId, .suggestions(.appendSuggestion($0))) }
            + [.delta(partId: partId, .endPart)]
    }

    /// The authoritative `part` for a suggestions collection.
    func suggestionsPart(_ cards: [Suggestions.Card], partId: String = "sug") -> StreamEvent {
        .part(.suggestions(Suggestions(partId: partId, suggestions: cards)))
    }

    /// A request_image_upload marker fixture — contract defaults unless overridden.
    func requestImageUpload(
        partId: String = "part_upload_1",
        acceptedTypes: [String] = RequestImageUpload.defaultAcceptedTypes,
        maxSizeBytes: Int = RequestImageUpload.defaultMaxSizeBytes
    ) -> RequestImageUpload {
        RequestImageUpload(partId: partId, acceptedTypes: acceptedTypes, maxSizeBytes: maxSizeBytes)
    }

    /// The authoritative `part` for a request_image_upload marker.
    func requestImageUploadPart(_ marker: RequestImageUpload) -> StreamEvent {
        .part(.requestImageUpload(marker))
    }

    /// A contact-form fixture (name / email / message).
    func contactForm(partId: String = "part_contact_1") -> ConversationForm {
        .contact(ShowContactForm(partId: partId, fields: Self.standardFormFields))
    }

    /// A support-ticket fixture.
    func ticketForm(partId: String = "part_ticket_1") -> ConversationForm {
        .supportTicket(ShowSupportTicket(
            partId: partId,
            fields: Self.standardFormFields,
            attachmentsAccepted: true,
            maxAttachmentSizeBytes: 2_097_152
        ))
    }

    /// A custom-form fixture.
    func customForm(partId: String = "part_form_1") -> ConversationForm {
        .custom(ShowForm(
            partId: partId,
            formId: "salesLead",
            name: "Sales lead",
            confirmationText: "Thanks!",
            fields: Self.standardFormFields,
            minFilledFields: 1
        ))
    }

    /// The authoritative `part` for any form marker.
    func formPart(_ part: Part) -> StreamEvent {
        .part(part)
    }

    static let standardFormFields: [FormField] = [
        .init(key: "name", label: "Name", type: .text, required: true),
        .init(key: "email", label: "Email", type: .email, required: true),
        .init(key: "message", label: "Message", type: .textarea, required: true)
    ]

    /// An assistant-sent image fixture.
    func messageImage(
        url: String = "https://cdn.example.com/uploads/receipt.jpg",
        caption: String? = "Receipt"
    ) -> MessageImage {
        MessageImage(
            url: URL(string: url)!,
            thumbnailUrl: URL(string: "https://cdn.example.com/uploads/receipt_thumb.jpg"),
            caption: caption
        )
    }

    /// An assistant-sent file fixture.
    func messageFile(
        filename: String = "invoice.pdf",
        url: String = "https://cdn.example.com/invoice.pdf"
    ) -> MessageFile {
        MessageFile(
            filename: filename,
            url: URL(string: url)!,
            mimeType: "application/pdf",
            sizeBytes: 48231
        )
    }

    /// The terminal `done` event carrying the given parts.
    func doneMessage(parts: [Part]) -> StreamEvent {
        .done(
            Message(
                messageId: "done",
                role: .assistant,
                parts: parts,
                createdAt: "2026-01-01T00:00:00.000Z"
            ),
            visitorToken: nil
        )
    }
}

private struct TestError: Error {}
