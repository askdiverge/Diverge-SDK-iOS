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
        var submitActionResponse: SubmitActionResponse?
        var submitActionError: ChatServiceError?
        var rateError: ChatServiceError?
        var livechatFeedbackResponse: LivechatFeedbackResponse?
        var livechatFeedbackError: ChatServiceError?
        var livechatState: LivechatState = LivechatState(status: .inactive)
        var livechatStateError: ChatServiceError?
        /// Thrown by the `fetchLivechatState` calls at these zero-based indices only.
        var livechatStateFailingCalls: [Int: ChatServiceError] = [:]
        var livechatHandoverError: ChatServiceError?
        var livechatMessagePages: [LivechatMessagePage] = []
        var livechatMessagesError: ChatServiceError?
        var livechatSendResponse: LivechatMessage?
        var livechatSendError: ChatServiceError?
        var livechatTypingError: ChatServiceError?
        var livechatCloseError: ChatServiceError?
        var formDefinition: ChatFormDefinition?
        var formError: ChatServiceError?
        var sessionState: ChatSessionState = ChatSessionState()
        var sessionError: ChatServiceError?
        var patchFormValuesError: ChatServiceError?
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
    nonisolated(unsafe) private(set) var lastSubmitAction: SubmitActionRequest?
    nonisolated(unsafe) private(set) var submitActionCallCount = 0
    nonisolated(unsafe) private(set) var lastRateRequest: RateConversationRequest?
    nonisolated(unsafe) private(set) var rateCallCount = 0
    nonisolated(unsafe) private(set) var livechatFeedbackCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatFeedbackRequest: RateConversationRequest?
    nonisolated(unsafe) private(set) var livechatStateCallCount = 0
    nonisolated(unsafe) private(set) var livechatHandoverCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatHandoverSource: String?
    nonisolated(unsafe) private(set) var lastLivechatHandoverPartId: String?
    nonisolated(unsafe) private(set) var lastLivechatHandoverClientContext: LivechatClientContext?
    nonisolated(unsafe) private(set) var livechatMessagesCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatAfterSequence: Int64?
    nonisolated(unsafe) private(set) var livechatSendCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatSendText: String?
    nonisolated(unsafe) private(set) var livechatTypingCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatTyping: Bool?
    nonisolated(unsafe) private(set) var livechatCloseCallCount = 0
    nonisolated(unsafe) private(set) var lastLivechatCloseReason: String?
    nonisolated(unsafe) private(set) var fetchFormCallCount = 0
    nonisolated(unsafe) private(set) var lastFetchFormId: String?
    nonisolated(unsafe) private(set) var fetchSessionCallCount = 0
    nonisolated(unsafe) private(set) var patchFormValuesCallCount = 0
    nonisolated(unsafe) private(set) var lastPatchFormId: String?
    nonisolated(unsafe) private(set) var lastPatchFormValues: [String: String]?

    /// Mutable so poller tests can change status / errors between ticks.
    nonisolated(unsafe) var livechatState: LivechatState
    nonisolated(unsafe) var livechatStateError: ChatServiceError?
    nonisolated(unsafe) var livechatStateFailingCalls: [Int: ChatServiceError]
    nonisolated(unsafe) var livechatMessagePages: [LivechatMessagePage]
    /// Awaited inside `sendLivechatMessage` so a test can `appendLivechat` while the send is in flight.
    nonisolated(unsafe) var livechatSendHold: (@Sendable () async -> Void)?
    nonisolated(unsafe) var formDefinition: ChatFormDefinition?
    nonisolated(unsafe) var sessionState: ChatSessionState
    nonisolated(unsafe) var patchFormValuesError: ChatServiceError?

    init(_ stub: Stub = .init()) {
        self.stub = stub
        self.livechatState = stub.livechatState
        self.livechatStateError = stub.livechatStateError
        self.livechatStateFailingCalls = stub.livechatStateFailingCalls
        self.livechatMessagePages = stub.livechatMessagePages
        self.formDefinition = stub.formDefinition
        self.sessionState = stub.sessionState
        self.patchFormValuesError = stub.patchFormValuesError
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

    func submitAction(_ request: SubmitActionRequest) async throws(ChatServiceError) -> SubmitActionResponse {
        self.submitActionCallCount += 1
        self.lastSubmitAction = request
        if let error = self.stub.submitActionError {
            throw error
        }
        return self.stub.submitActionResponse
            ?? SubmitActionResponse(submissionId: "sub_test", confirmationText: "Thanks!")
    }

    func rateConversation(_ request: RateConversationRequest) async throws(ChatServiceError) {
        self.rateCallCount += 1
        self.lastRateRequest = request
        if let error = self.stub.rateError {
            throw error
        }
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

    func fetchLivechatState() async throws(ChatServiceError) -> LivechatState {
        let index = self.livechatStateCallCount
        self.livechatStateCallCount += 1
        if let error = self.livechatStateFailingCalls[index] ?? self.livechatStateError {
            throw error
        }
        return self.livechatState
    }

    func requestLivechatHandover(
        source: String,
        partId: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError) {
        self.livechatHandoverCallCount += 1
        self.lastLivechatHandoverSource = source
        self.lastLivechatHandoverPartId = partId
        self.lastLivechatHandoverClientContext = clientContext
        if let error = self.stub.livechatHandoverError { throw error }
    }

    func fetchLivechatMessages(after sequenceNumber: Int64?) async throws(ChatServiceError) -> LivechatMessagePage {
        self.livechatMessagesCallCount += 1
        self.lastLivechatAfterSequence = sequenceNumber
        if let error = self.stub.livechatMessagesError { throw error }
        let index = self.livechatMessagesCallCount - 1
        if index < self.livechatMessagePages.count {
            return self.livechatMessagePages[index]
        }
        return LivechatMessagePage(messages: [], hasMore: false)
    }

    func sendLivechatMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) async throws(ChatServiceError) -> LivechatMessage {
        self.livechatSendCallCount += 1
        self.lastLivechatSendText = text
        if let hold = self.livechatSendHold {
            await hold()
        }
        if let error = self.stub.livechatSendError { throw error }
        if let response = self.stub.livechatSendResponse { return response }
        return LivechatMessage(
            messageId: "livechat_msg_\(self.livechatSendCallCount)",
            role: .user,
            parts: [.unknown],
            createdAt: "2025-01-01T00:00:00Z",
            sequenceNumber: Int64(self.livechatSendCallCount)
        )
    }

    func sendLivechatTyping(isTyping: Bool) async throws(ChatServiceError) {
        self.livechatTypingCallCount += 1
        self.lastLivechatTyping = isTyping
        if let error = self.stub.livechatTypingError { throw error }
    }

    func closeLivechat(reason: String?) async throws(ChatServiceError) {
        self.livechatCloseCallCount += 1
        self.lastLivechatCloseReason = reason
        if let error = self.stub.livechatCloseError { throw error }
    }

    func submitLivechatFeedback(
        _ request: RateConversationRequest
    ) async throws(ChatServiceError) -> LivechatFeedbackResponse {
        self.livechatFeedbackCallCount += 1
        self.lastLivechatFeedbackRequest = request
        if let error = self.stub.livechatFeedbackError {
            throw error
        }
        return self.stub.livechatFeedbackResponse
            ?? LivechatFeedbackResponse(
                livechatSessionId: "lc_test",
                status: "submitted",
                rating: request.rating,
                feedback: request.feedback,
                submittedAt: "2026-01-01T00:00:00Z"
            )
    }

    func fetchForm(id: String) async throws(ChatServiceError) -> ChatFormDefinition {
        self.fetchFormCallCount += 1
        self.lastFetchFormId = id
        if let error = self.stub.formError { throw error }
        if let form = self.formDefinition { return form }
        throw ChatServiceError.transport(.http(.unhandled(status: 404)))
    }

    func fetchSession() async throws(ChatServiceError) -> ChatSessionState {
        self.fetchSessionCallCount += 1
        if let error = self.stub.sessionError { throw error }
        return self.sessionState
    }

    func patchFormValues(
        formId: String,
        values: [String: String]
    ) async throws(ChatServiceError) -> ChatSessionState {
        self.patchFormValuesCallCount += 1
        self.lastPatchFormId = formId
        self.lastPatchFormValues = values
        if let error = self.patchFormValuesError ?? self.stub.patchFormValuesError {
            throw error
        }
        let updated = values.map { ChatSessionValue(key: $0.key, value: $0.value) }
        self.sessionState = ChatSessionState(values: updated)
        return self.sessionState
    }
}
