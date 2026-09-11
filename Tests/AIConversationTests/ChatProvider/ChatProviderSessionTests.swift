//
//  ChatProviderSessionTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatProvider — reset, delete and export")
struct ChatProviderSessionTests: ChatProviderTestHelpers {

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
}
