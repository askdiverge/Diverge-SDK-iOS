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
/// race: each write happens-before the test's read across the `await`. `LivechatSession`
/// tests change the livechat stubs only while the poller is suspended in its sleep seam.
final class MockChatService: ChatServicing {

    struct Stub {
        var sendEvents: [StreamEvent] = []
        var sendError: ChatServiceError?
        var historyPages: [MessagePage] = []
        var historyError: ChatServiceError?
        var resetError: ChatServiceError?
        var deleteError: ChatServiceError?
        var livechatState = LivechatState(status: .inactive)
        var livechatStateError: ChatServiceError?
        /// Thrown by the `fetchLivechatState` calls at these zero-based indices only.
        var livechatStateFailingCalls: [Int: ChatServiceError] = [:]
        var livechatHandoverError: ChatServiceError?
        var livechatHandoverStatus: LivechatState.Status = .waiting
        var livechatMessagePages: [LivechatMessagePage] = []
        var livechatSendResponse: LivechatMessage?
        var livechatSendError: ChatServiceError?
        var livechatCloseError: ChatServiceError?
    }

    private let stub: Stub

    nonisolated(unsafe) private(set) var historyCallCount = 0
    nonisolated(unsafe) private(set) var resetCallCount = 0
    nonisolated(unsafe) private(set) var deleteCallCount = 0
    nonisolated(unsafe) private(set) var livechatStateCallCount = 0
    nonisolated(unsafe) private(set) var livechatHandoverCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatHandoverClientContext: LivechatClientContext?
    nonisolated(unsafe) private(set) var livechatMessagesCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatAfterSequence: Int64?
    nonisolated(unsafe) private(set) var livechatCloseCallCount = 0

    nonisolated(unsafe) var livechatState: LivechatState
    nonisolated(unsafe) var livechatStateError: ChatServiceError?
    nonisolated(unsafe) var livechatMessagePages: [LivechatMessagePage]
    /// Awaited after `sendEvents` and before the reply stream finishes.
    nonisolated(unsafe) var sendHold: (@Sendable () async -> Void)?
    /// Awaited inside `sendLivechatMessage`, so a test can act while the POST is in flight.
    nonisolated(unsafe) var livechatSendHold: (@Sendable () async -> Void)?

    init(_ stub: Stub = .init()) {
        self.stub = stub
        self.livechatState = stub.livechatState
        self.livechatStateError = stub.livechatStateError
        self.livechatMessagePages = stub.livechatMessagePages
    }

    func sendMessage(_ text: String, page: String?) -> AsyncThrowingStream<StreamEvent, any Error> {
        let events = self.stub.sendEvents
        let error = self.stub.sendError
        guard let hold = self.sendHold else {
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
        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    continuation.yield(event)
                }
                await hold()
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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

    func submitAction(_: SubmitActionRequest) async throws(ChatServiceError) -> SubmitActionResponse {
        throw .provider(Unstubbed())
    }

    func fetchForm(id _: String) async throws(ChatServiceError) -> ChatFormDefinition {
        throw .provider(Unstubbed())
    }

    func fetchLivechatState() async throws(ChatServiceError) -> LivechatState {
        let index = self.livechatStateCallCount
        self.livechatStateCallCount += 1
        if let error = self.stub.livechatStateFailingCalls[index] ?? self.livechatStateError {
            throw error
        }
        return self.livechatState
    }

    func requestLivechatHandover(
        source _: LivechatHandoverRequest.Source,
        partId _: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError) -> LivechatState.Status {
        self.livechatHandoverCallCount += 1
        self.lastLivechatHandoverClientContext = clientContext
        if let error = self.stub.livechatHandoverError {
            throw error
        }
        return self.stub.livechatHandoverStatus
    }

    func fetchLivechatMessages(after sequenceNumber: Int64?) async throws(ChatServiceError) -> LivechatMessagePage {
        let index = self.livechatMessagesCallCount
        self.livechatMessagesCallCount += 1
        self.lastLivechatAfterSequence = sequenceNumber
        return index < self.livechatMessagePages.count
        ? self.livechatMessagePages[index]
        : LivechatMessagePage(messages: [], hasMore: false)
    }

    func sendLivechatMessage(_ text: String, page _: String?) async throws(ChatServiceError) -> LivechatMessage {
        await self.livechatSendHold?()
        if let error = self.stub.livechatSendError {
            throw error
        }
        return self.stub.livechatSendResponse ?? LivechatFixtures.message("stored", role: .user, text: text)
    }

    func sendLivechatTyping(isTyping _: Bool) async throws(ChatServiceError) {}

    func closeLivechat(reason _: String?) async throws(ChatServiceError) {
        self.livechatCloseCallCount += 1
        if let error = self.stub.livechatCloseError {
            throw error
        }
    }

    /// Thrown by calls `ChatProvider` does not make yet, so an unexpected call fails loudly.
    private struct Unstubbed: Error {}
}
