//
//  MockChatService.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
@testable import AIConversationEngine

/// Drives `ChatProvider` with a scripted facade. The provider serializes every call —
/// one actor, each op awaited in turn — so the `nonisolated(unsafe)` call counters never
/// race: each write happens-before the test's read across the `await`.
final class MockChatService: ChatServicing {

    struct Stub {
        var sendEvents: [StreamEvent] = []
        var sendError: ChatServiceError?
        var historyPages: [MessagePage] = []
        var historyError: ChatServiceError?
        var resetError: ChatServiceError?
        var deleteError: ChatServiceError?
    }

    private let stub: Stub

    nonisolated(unsafe) private(set) var historyCallCount = 0
    nonisolated(unsafe) private(set) var resetCallCount = 0
    nonisolated(unsafe) private(set) var deleteCallCount = 0

    init(_ stub: Stub = .init()) {
        self.stub = stub
    }

    func sendMessage(_ text: String, page: String?) -> AsyncThrowingStream<StreamEvent, any Error> {
        let events = self.stub.sendEvents
        let error = self.stub.sendError
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func fetchHistory(cursor: String?) async throws(ChatServiceError) -> MessagePage {
        let index = self.historyCallCount
        self.historyCallCount += 1
        if let error = self.stub.historyError {
            throw error
        }
        return index < self.stub.historyPages.count
        ? self.stub.historyPages[index]
        : MessagePage(messages: [], nextCursor: nil)
    }

    func resetConversation() async throws(ChatServiceError) {
        self.resetCallCount += 1
        if let error = self.stub.resetError {
            throw error
        }
    }

    func deleteData() async throws(ChatServiceError) {
        self.deleteCallCount += 1
        if let error = self.stub.deleteError {
            throw error
        }
    }
}
