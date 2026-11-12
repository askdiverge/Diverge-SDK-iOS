//
//  ChatService+Livechat.swift
//  AIConversationEngine
//

import Foundation
import AIConversationCore

extension ChatService {

    /// The `GET /livechat/sync` query item carrying the message cursor: the highest sequence
    /// number already published, so the API returns only newer messages.
    package static let livechatAfterSequenceQueryItem = "after_sequence_number"
    /// The `GET /livechat/sync` query item asking the server to hold the request until the state
    /// or the log changes, for at most this many milliseconds.
    package static let livechatWaitQueryItem = "wait_ms"
    /// The `GET /livechat/sync` query item carrying the change hint from the previous response,
    /// which the server waits on.
    package static let livechatSyncCursorQueryItem = "sync_cursor"

    package func syncLivechat(
        after sequenceNumber: Int64?,
        waitMs: Int?,
        syncCursor: String?
    ) async throws(ChatServiceError) -> LivechatSync {
        var queryItems: [URLQueryItem] = []
        if let sequenceNumber {
            queryItems.append(URLQueryItem(name: Self.livechatAfterSequenceQueryItem, value: String(sequenceNumber)))
        }
        if let waitMs, let syncCursor {
            queryItems.append(URLQueryItem(name: Self.livechatWaitQueryItem, value: String(waitMs)))
            queryItems.append(URLQueryItem(name: Self.livechatSyncCursorQueryItem, value: syncCursor))
        }
        let base = self.url(for: .livechatSync)
        let url = queryItems.isEmpty ? base : base.appending(queryItems: queryItems)
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(url: url, headers: self.headers(token: token))
            }
        }
    }

    package func requestLivechatHandover(
        source: LivechatHandoverRequest.Source,
        partId: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError) -> LivechatState.Status {
        let request = LivechatHandoverRequest(source: source, partId: partId, clientContext: clientContext)
        do {
            let response: LivechatSessionResponse = try await self.mappingErrors {
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    try await self.network.post(
                        url: self.url(for: .livechatHandover),
                        payload: request,
                        headers: self.headers(token: token)
                    )
                }
            }
            return response.status
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        }
    }

    package func sendLivechatMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?,
        operationId: String
    ) async throws(ChatServiceError) -> LivechatMessage {
        let payload = LivechatVisitorMessageRequest(
            message: .init(parts: SendMessageRequest.Part.make(text: text, attachments: attachments)),
            context: page.map { .init(page: $0) },
            clientOperationId: operationId
        )
        do {
            let response: LivechatVisitorMessageResponse = try await self.mappingErrors {
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    try await self.network.post(
                        url: self.url(for: .livechatMessages),
                        payload: payload,
                        headers: self.headers(token: token)
                    )
                }
            }
            return response.message
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        }
    }

    package func sendLivechatTyping(isTyping: Bool) async throws(ChatServiceError) {
        try await self.postLivechat(LivechatTypingRequest(isTyping: isTyping), to: .livechatTyping)
    }

    package func closeLivechat(reason: String?) async throws(ChatServiceError) {
        do {
            try await self.postLivechat(LivechatCloseRequest(reason: reason), to: .livechatClose)
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        }
    }

    package func submitLivechatFeedback(_ request: LivechatFeedbackRequest) async throws(ChatServiceError) {
        do {
            try await self.postLivechat(request, to: .livechatFeedback)
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        }
    }

    /// Rates the active conversation 1–5 with optional feedback. The response is an empty 200;
    /// subsequent calls overwrite the previous rating.
    package func rateConversation(
        _ request: RateConversationRequest
    ) async throws(ChatServiceError) {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .rate),
                    payload: request,
                    headers: self.headers(token: token)
                )
            }
        }
    }

    /// Session-bound POST to a livechat endpoint whose response the client doesn't need.
    func postLivechat(
        _ payload: some Encodable & Sendable,
        to endpoint: Endpoint
    ) async throws(ChatServiceError) {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: endpoint),
                    payload: payload,
                    headers: self.headers(token: token)
                )
            }
        }
    }
}
