//
//  ChatProviderHistoryTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — history pagination and welcome")
struct ChatProviderHistoryTests: ChatProviderTestHelpers {

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
}
