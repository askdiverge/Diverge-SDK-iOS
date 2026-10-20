//
//  MockChatService.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Synchronization
@testable import AIConversationEngine

/// Drives `ChatProvider` with a scripted facade. The provider serializes every call —
/// one actor, each op awaited in turn — so the `nonisolated(unsafe)` call counters never
/// race: each write happens-before the test's read across the `await`. `LivechatSession`
/// tests change the livechat stubs only while the poller is suspended in its sleep seam.
/// Typing posts run on the session's own task while tests poll for them, so their log and
/// failure count sit behind a `Mutex`.
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
        /// Thrown by the `syncLivechat` calls at these zero-based indices only.
        var livechatStateFailingCalls: [Int: ChatServiceError] = [:]
        /// Returned instead of `livechatState` by the `syncLivechat` calls at these indices only.
        var livechatStateByCall: [Int: LivechatState] = [:]
        var livechatHandoverError: ChatServiceError?
        var livechatHandoverStatus: LivechatState.Status = .waiting
        /// The messages of each `syncLivechat` call, by call index; later calls return none.
        var livechatMessagePages: [LivechatFixtures.Page] = []
        var livechatSendResponse: LivechatMessage?
        var livechatSendError: ChatServiceError?
        /// Thrown by the `sendLivechatMessage` calls at these zero-based indices only.
        var livechatSendFailingCalls: [Int: ChatServiceError] = [:]
        var livechatCloseError: ChatServiceError?
        /// The first this many typing posts fail with a connection error.
        var livechatTypingFailures = 0
        /// Thrown by every typing post after the `livechatTypingFailures`.
        var livechatTypingError: ChatServiceError?
    }

    private let stub: Stub

    nonisolated(unsafe) private(set) var historyCallCount = 0
    nonisolated(unsafe) private(set) var resetCallCount = 0
    nonisolated(unsafe) private(set) var deleteCallCount = 0
    nonisolated(unsafe) private(set) var livechatSyncCallCount = 0
    /// The `wait_ms` and `sync_cursor` of the last `syncLivechat` call.
    nonisolated(unsafe) private(set) var lastLivechatSyncWait: (waitMs: Int?, syncCursor: String?)
    nonisolated(unsafe) private(set) var livechatHandoverCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatHandoverClientContext: LivechatClientContext?
    nonisolated(unsafe) private(set) var lastLivechatHandoverSource: LivechatHandoverRequest.Source?
    nonisolated(unsafe) private(set) var lastLivechatHandoverPartId: String?
    nonisolated(unsafe) private(set) var lastLivechatAfterSequence: Int64?
    nonisolated(unsafe) private(set) var livechatCloseCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatCloseReason: String?
    /// The operation id of each `sendLivechatMessage` call, in order.
    nonisolated(unsafe) private(set) var livechatSendOperationIds: [String] = []
    /// The typing posts that succeeded, in order.
    var livechatTypingEvents: [Bool] { self.typingLog.withLock { $0 } }
    private let typingLog = Mutex<[Bool]>([])
    private let typingFailuresLeft: Mutex<Int>
    /// Every typing post, failed or not.
    var livechatTypingAttempts: Int { self.typingAttemptCount.withLock { $0 } }
    private let typingAttemptCount = Mutex(0)

    nonisolated(unsafe) var livechatState: LivechatState
    nonisolated(unsafe) var livechatStateError: ChatServiceError?
    nonisolated(unsafe) var livechatMessagePages: [LivechatFixtures.Page]
    /// The `sync_cursor` every `syncLivechat` response carries.
    nonisolated(unsafe) var livechatSyncCursor: String?
    /// Awaited after `sendEvents` and before the reply stream finishes.
    nonisolated(unsafe) var sendHold: (@Sendable () async -> Void)?
    /// Awaited at the start of each `syncLivechat`, so a test can act while the read is in flight.
    nonisolated(unsafe) var livechatSyncHold: (@Sendable () async -> Void)?
    /// Awaited inside `sendLivechatMessage`, so a test can act while the POST is in flight.
    nonisolated(unsafe) var livechatSendHold: (@Sendable () async -> Void)?
    /// Awaited at the start of each typing post with its value, so a test can act while it is
    /// in flight.
    nonisolated(unsafe) var livechatTypingHold: (@Sendable (Bool) async -> Void)?

    init(_ stub: Stub = .init()) {
        self.stub = stub
        self.livechatState = stub.livechatState
        self.livechatStateError = stub.livechatStateError
        self.livechatMessagePages = stub.livechatMessagePages
        self.typingFailuresLeft = Mutex(stub.livechatTypingFailures)
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

    func syncLivechat(
        after sequenceNumber: Int64?,
        waitMs: Int?,
        syncCursor: String?
    ) async throws(ChatServiceError) -> LivechatSync {
        let index = self.livechatSyncCallCount
        self.livechatSyncCallCount += 1
        await self.livechatSyncHold?()
        self.lastLivechatAfterSequence = sequenceNumber
        self.lastLivechatSyncWait = (waitMs, syncCursor)
        if let error = self.stub.livechatStateFailingCalls[index] ?? self.livechatStateError {
            throw error
        }
        let page = index < self.livechatMessagePages.count ? self.livechatMessagePages[index] : .init(messages: [])
        return LivechatSync(
            state: self.stub.livechatStateByCall[index] ?? self.livechatState,
            messages: page.messages,
            hasMore: page.hasMore,
            syncCursor: self.livechatSyncCursor
        )
    }

    func requestLivechatHandover(
        source: LivechatHandoverRequest.Source,
        partId: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError) -> LivechatState.Status {
        self.livechatHandoverCallCount += 1
        self.lastLivechatHandoverSource = source
        self.lastLivechatHandoverPartId = partId
        self.lastLivechatHandoverClientContext = clientContext
        if let error = self.stub.livechatHandoverError {
            throw error
        }
        return self.stub.livechatHandoverStatus
    }

    func sendLivechatMessage(
        _ text: String,
        page _: String?,
        operationId: String
    ) async throws(ChatServiceError) -> LivechatMessage {
        let index = self.livechatSendOperationIds.count
        self.livechatSendOperationIds.append(operationId)
        await self.livechatSendHold?()
        if let error = self.stub.livechatSendFailingCalls[index] ?? self.stub.livechatSendError {
            throw error
        }
        return self.stub.livechatSendResponse ?? LivechatFixtures.message("stored", role: .user, text: text)
    }

    func sendLivechatTyping(isTyping: Bool) async throws(ChatServiceError) {
        self.typingAttemptCount.withLock { $0 += 1 }
        await self.livechatTypingHold?(isTyping)
        let fails = self.typingFailuresLeft.withLock { left in
            defer { left = max(0, left - 1) }
            return left > 0
        }
        if fails {
            throw .transport(.connection(URLError(.networkConnectionLost)))
        }
        if let error = self.stub.livechatTypingError {
            throw error
        }
        self.typingLog.withLock { $0.append(isTyping) }
    }

    func closeLivechat(reason: String?) async throws(ChatServiceError) {
        self.livechatCloseCallCount += 1
        self.lastLivechatCloseReason = reason
        if let error = self.stub.livechatCloseError {
            throw error
        }
    }

    /// Thrown by calls `ChatProvider` does not make yet, so an unexpected call fails loudly.
    private struct Unstubbed: Error {}
}
