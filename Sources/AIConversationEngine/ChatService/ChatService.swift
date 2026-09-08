//
//  ChatService.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-04.
//

import Foundation
import AIConversationCore

/// Concrete SDK facade over the Dialoge chat API.
package final class ChatService: Sendable {

    package static let productionBaseURL = URL(string: "https://api.dialogintelligens.dk")!

    private let network: NetworkManager
    private let tokenStore: TokenStore
    private let baseURL: URL

    package init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        onResetConversation: @escaping @Sendable () async throws -> String,
        onDeleteData: @escaping @Sendable () async throws -> Void,
        baseURL: URL = ChatService.productionBaseURL,
        session: URLSession = ChatService.makeSession()
    ) {
        self.baseURL = baseURL
        self.tokenStore = TokenStore(
            tokenProvider: tokenProvider,
            onResetConversation: onResetConversation,
            onDeleteData: onDeleteData
        )
        self.network = NetworkManager(
            decoder: Self.decoder(baseURL: baseURL),
            encoder: Self.encoder,
            session: session
        )
    }
}

extension ChatService {

    package func fetchConfig() async throws(ChatServiceError) -> ChatConfig {
        // Session agnostic setup — a 401 is recoverable, retry once.
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .retryOnce) { token in
                try await self.network.get(
                    url: self.url(for: .config),
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func fetchData(_ url: URL) async throws(ChatServiceError) -> Data {
        // Inline data URLs (visitor uploads echoed by the API) decode without a network hop.
        if url.scheme?.lowercased() == "data" {
            return try await self.mappingErrors {
                try Data(contentsOf: url)
            }
        }
        // Unauthenticated — no bearer token is attached.
        return try await self.mappingErrors {
            try await self.network.data(from: url, headers: nil)
        }
    }
}

extension ChatService: ChatServicing {

    package func fetchHistory(cursor: String?) async throws(ChatServiceError) -> MessagePage {
        var queryItems = [URLQueryItem(name: "limit", value: String(Self.historyPageLimit))]
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        let url = self.url(for: .messages).appending(queryItems: queryItems)
        // Session bound — a 401 means the conversation expired, surface it.
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(url: url, headers: Self.headers(token: token))
            }
        }
    }

    package func sendMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        let parts = SendMessageRequest.Part.make(text: text, attachments: attachments)

        let (stream, continuation) = AsyncThrowingStream<StreamEvent, any Error>.makeStream()

        guard !parts.isEmpty else {
            assertionFailure("sendMessage called with neither text nor attachments")
            continuation.finish(throwing: ChatServiceError.invalidRequest("Send requires text or an attachment"))
            return stream
        }

        let payload = SendMessageRequest(
            message: .init(parts: parts),
            context: page.map { .init(page: $0) }
        )

        let task = Task {
            do {
                // Session bound — a 401 means the conversation expired, surface it.
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    var headers = Self.headers(token: token)
                    headers["Accept"] = "text/event-stream"

                    let events: AsyncThrowingStream<StreamEvent, any Error> = self.network.stream(
                        url: self.url(for: .messages),
                        payload: payload,
                        headers: headers
                    )

                    for try await event in events {
                        // remap event error to throwing Error for singel error path
                        if case .error(let failure) = event {
                            throw ChatServiceError.stream(failure)
                        }
                        // `.done` is terminal per the SSE contract. Adopt the conversation-bound
                        // token it may carry *before* yielding, so the consumer's very next
                        // send already goes out on the same thread.
                        if case .done(_, let visitorToken?) = event {
                            await self.tokenStore.adopt(visitorToken)
                        }
                        continuation.yield(event)
                        if case .done = event { return }
                    }
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: ChatServiceError(error))
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }

        return stream
    }

    package func submitAction(
        _ request: SubmitActionRequest
    ) async throws(ChatServiceError) -> SubmitActionResponse {
        // Strategy-free encode so dictionary field keys (e.g. `orderNumber`) stay verbatim —
        // `convertToSnakeCase` would rewrite them and the server would not recognise them.
        let body: Data
        do {
            body = try Self.actionsEncoder.encode(request)
        } catch {
            throw ChatServiceError.invalidRequest("Failed to encode action request")
        }
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .actions),
                    body: body,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func rateConversation(
        _ request: RateConversationRequest
    ) async throws(ChatServiceError) {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .rate),
                    payload: request,
                    headers: Self.headers(token: token)
                )
            }
        }
    }


    package func fetchLivechatState() async throws(ChatServiceError) -> LivechatState {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(
                    url: self.url(for: .livechatState),
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func requestLivechatHandover(
        source: String,
        partId: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError) {
        let request = LivechatHandoverRequest(
            platform: LivechatHandoverRequest.mobileAppPlatform,
            source: source,
            partId: partId,
            clientContext: clientContext
        )
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .livechatHandover),
                    payload: request,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func fetchLivechatMessages(
        after sequenceNumber: Int64?
    ) async throws(ChatServiceError) -> LivechatMessagePage {
        var queryItems: [URLQueryItem] = []
        if let sequenceNumber {
            queryItems.append(
                URLQueryItem(name: "after_sequence_number", value: String(sequenceNumber))
            )
        }
        let base = self.url(for: .livechatMessages)
        let url = queryItems.isEmpty ? base : base.appending(queryItems: queryItems)
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(
                    url: url,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func sendLivechatMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) async throws(ChatServiceError) -> LivechatMessage {
        let parts = SendMessageRequest.Part.make(text: text, attachments: attachments)
        guard !parts.isEmpty else {
            throw ChatServiceError.invalidRequest("Livechat send requires text or an attachment")
        }
        let payload = SendMessageRequest(
            message: .init(parts: parts),
            context: page.map { .init(page: $0) }
        )
        // Response is LivechatVisitorMessageResponse with nested `message`; decode the envelope.
        let envelope: LivechatVisitorMessageEnvelope = try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .livechatMessages),
                    payload: payload,
                    headers: Self.headers(token: token)
                )
            }
        }
        return envelope.message
    }

    package func sendLivechatTyping(isTyping: Bool) async throws(ChatServiceError) {
        let request = LivechatTypingRequest(isTyping: isTyping)
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .livechatTyping),
                    payload: request,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func closeLivechat(reason: String?) async throws(ChatServiceError) {
        let request = LivechatCloseRequest(reason: reason)
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .livechatClose),
                    payload: request,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func submitLivechatFeedback(
        _ request: RateConversationRequest
    ) async throws(ChatServiceError) -> LivechatFeedbackResponse {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.post(
                    url: self.url(for: .livechatFeedback),
                    payload: request,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func fetchForm(id: String) async throws(ChatServiceError) -> ChatFormDefinition {
        let url = self.url(for: .forms).appending(path: id)
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(
                    url: url,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func fetchSession() async throws(ChatServiceError) -> ChatSessionState {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(
                    url: self.url(for: .session),
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func patchFormValues(
        formId: String,
        values: [String: String]
    ) async throws(ChatServiceError) -> ChatSessionState {
        // Strategy-free encode so dictionary field keys stay verbatim.
        let body: Data
        do {
            body = try Self.actionsEncoder.encode(ChatFormValuesPatchRequest(values: values))
        } catch {
            throw ChatServiceError.invalidRequest("Failed to encode form values")
        }
        let url = self.url(for: .forms).appending(path: formId).appending(path: "values")
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.patch(
                    url: url,
                    body: body,
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    package func resetConversation() async throws(ChatServiceError) {
        try await self.mappingErrors {
            try await self.tokenStore.reset()
        }
    }

    package func deleteData() async throws(ChatServiceError) {
        try await self.mappingErrors {
            try await self.tokenStore.delete()
        }
    }

    package func exportMyData() async throws(ChatServiceError) -> Data {
        // Session bound — a 401 means the conversation expired, surface it.
        // Unlike delete, success leaves the bearer in place so the visitor can keep chatting.
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.data(
                    from: self.url(for: .export),
                    headers: Self.headers(token: token)
                )
            }
        }
    }

    /// In-chat promo banners for the current page. Session-bound; a 401 surfaces as
    /// ``ChatServiceError/sessionExpired``. Pass the same page string ``contextProvider``
    /// returns for start-prompt matching. Callers soft-fail on transport / missing-route
    /// errors so an older API without this route does not brick bootstrap — they must
    /// still surface ``sessionExpired``.
    package func fetchBanners(url: String?) async throws(ChatServiceError) -> [ChatBanner] {
        var queryItems: [URLQueryItem] = []
        if let url, !url.isEmpty {
            queryItems.append(URLQueryItem(name: "url", value: url))
        }
        let endpoint = self.url(for: .banners)
        let requestURL = queryItems.isEmpty
            ? endpoint
            : endpoint.appending(queryItems: queryItems)
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                let list: ChatBannerList = try await self.network.get(
                    url: requestURL,
                    headers: Self.headers(token: token)
                )
                return list.banners
            }
        }
    }
}

private extension ChatService {

    /// Messages per history page
    private static let historyPageLimit = 100

    static func headers(token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }

    /// RAM-only by design: no disk cache, cookies, or credential storage
    /// conversation data and bearer tokens never persist.
    ///
    /// Session-level headers apply only when a request doesn't set the same
    /// header itself — the SSE request overrides `Accept` with `text/event-stream`.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        return URLSession(configuration: configuration)
    }

    /// `baseURL` is what host-less attachment paths resolve against — see `AttachmentURL`.
    static func decoder(baseURL: URL) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.userInfo[AttachmentURL.baseURLKey] = baseURL
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    /// Strategy-free encoder for ``SubmitActionRequest`` — dictionary field keys must stay
    /// verbatim; the struct's own snake_case names are spelled out in `CodingKeys`.
    static var actionsEncoder: JSONEncoder {
        JSONEncoder()
    }
}

private extension ChatService {

    /// Dialoge API endpoints. Paths live here — the host may override `baseURL`.
    enum Endpoint: String {
        case config = "api/v1/chat/config"
        case messages = "api/v1/chat/messages"
        case actions = "api/v1/chat/actions"
        case rate = "api/v1/chat/rate"
        case livechatState = "api/v1/chat/livechat/state"
        case livechatHandover = "api/v1/chat/livechat/handover"
        case livechatMessages = "api/v1/chat/livechat/messages"
        case livechatTyping = "api/v1/chat/livechat/typing"
        case livechatClose = "api/v1/chat/livechat/close"
        case livechatFeedback = "api/v1/chat/livechat/feedback"
        case export = "api/v1/chat/export"
        case banners = "api/v1/chat/banners"
        case forms = "api/v1/chat/forms"
        case session = "api/v1/chat/session"
    }

    func url(for endpoint: Endpoint) -> URL {
        self.baseURL.appending(path: endpoint.rawValue)
    }
}

private extension ChatService {

    /// Runs `work` and translates any lower-layer error into `ChatServiceError`.
    func mappingErrors<T: Sendable>(
        _ work: () async throws -> T
    ) async throws(ChatServiceError) -> T {
        do {
            return try await work()
        } catch {
            throw ChatServiceError(error)
        }
    }
}
