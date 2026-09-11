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
        /// Awaited after `sendEvents` and before `sendEventsAfterHold` / the finish, so a test can
        /// run another provider op (e.g. `loadOlder`) while the send is suspended mid-stream.
        var sendHold: (@Sendable () async -> Void)?
        var sendEventsAfterHold: [StreamEvent] = []
        var sendError: ChatServiceError?
        var historyPages: [MessagePage] = []
        /// Thrown by every `fetchHistory` call.
        var historyError: ChatServiceError?
        /// Thrown by the `fetchHistory` calls at these zero-based indices only — a transient
        /// failure the paginator should recover from on the next call.
        var historyFailingCalls: [Int: ChatServiceError] = [:]
        var resetError: ChatServiceError?
        var deleteError: ChatServiceError?
        var exportData: Data?
        var exportError: ChatServiceError?
    }

    private let stub: Stub

    nonisolated(unsafe) private(set) var historyCallCount = 0
    /// The cursor each `fetchHistory` call asked for, in call order.
    nonisolated(unsafe) private(set) var historyCursors: [String?] = []
    nonisolated(unsafe) private(set) var resetCallCount = 0
    nonisolated(unsafe) private(set) var deleteCallCount = 0
    nonisolated(unsafe) private(set) var exportCallCount = 0
    nonisolated(unsafe) private(set) var lastSendText: String?
    nonisolated(unsafe) private(set) var lastSendAttachments: [OutgoingAttachment] = []
    nonisolated(unsafe) private(set) var lastSendPage: String?

    init(_ stub: Stub = .init()) {
        self.stub = stub
    }

    func sendMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        self.lastSendText = text
        self.lastSendAttachments = attachments
        self.lastSendPage = page
        let events = self.stub.sendEvents
        let error = self.stub.sendError
        let finish: @Sendable (AsyncThrowingStream<StreamEvent, any Error>.Continuation) -> Void = { continuation in
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }

        guard let hold = self.stub.sendHold else {
            // Synchronous script — every event is buffered before the provider reads the first.
            return AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                finish(continuation)
            }
        }

        let after = self.stub.sendEventsAfterHold
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    continuation.yield(event)
                }
                await hold()
                for event in after {
                    continuation.yield(event)
                }
                finish(continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func fetchHistory(cursor: String?) async throws(ChatServiceError) -> MessagePage {
        let index = self.historyCallCount
        self.historyCallCount += 1
        self.historyCursors.append(cursor)
        if let error = self.stub.historyError ?? self.stub.historyFailingCalls[index] {
            throw error
        }
        // Pages are served by *successful* position so a retried call gets the page it missed.
        let served = index - self.stub.historyFailingCalls.keys.filter { $0 < index }.count
        return served < self.stub.historyPages.count
        ? self.stub.historyPages[served]
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

    func exportMyData() async throws(ChatServiceError) -> Data {
        self.exportCallCount += 1
        if let error = self.stub.exportError {
            throw error
        }
        return self.stub.exportData ?? Data(#"{"generated_at":"2026-01-01T00:00:00Z","chatbot_id":"bot","visitor_id":"v","session":{"values":[]},"conversations":[],"livechat_sessions":[],"attachments":[],"support_tickets":[],"webhook_events":[]}"#.utf8)
    }
}
