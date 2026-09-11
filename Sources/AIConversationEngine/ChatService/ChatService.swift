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

    /// Live production API — the default every host gets unless it overrides `baseURL`.
    package static let productionBaseURL = URL(string: "https://api.dialogintelligens.dk")!

    /// Carries the SDK release on every authenticated call, so the backend can log adoption
    /// and gate wire-contract changes per SDK version.
    package static let sdkVersionHeader = "X-Diverge-SDK-Version"

    /// Names the capability line the host embeds, so the backend can serve a reply the SDK
    /// can actually render. A ``ClientProfile/productRecommendation`` conversation must not
    /// be offered livechat handover or forms, which only exist on the customer-service line.
    package static let clientProfileHeader = "X-Diverge-Client-Profile"

    private let network: NetworkManager
    private let tokenStore: TokenStore
    private let baseURL: URL
    private let sdkVersion: String?
    private let clientProfile: ClientProfile?

    /// - Parameters:
    ///   - baseURL: Chatbot API host. Defaults to ``productionBaseURL``; a host overrides it to
    ///     reach a development or local stand-in backend.
    ///   - sdkVersion: SemVer of the embedding SDK release, sent as ``sdkVersionHeader``.
    ///     `nil` omits the header — the engine used standalone, or under test.
    ///   - clientProfile: Capability line, sent as ``clientProfileHeader``. `nil` omits it.
    package init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        onResetConversation: @escaping @Sendable () async throws -> String,
        onDeleteData: @escaping @Sendable () async throws -> Void,
        baseURL: URL = ChatService.productionBaseURL,
        session: URLSession = ChatService.makeSession(),
        sdkVersion: String? = nil,
        clientProfile: ClientProfile? = nil
    ) {
        self.baseURL = baseURL
        self.sdkVersion = sdkVersion
        self.clientProfile = clientProfile
        self.tokenStore = TokenStore(
            tokenProvider: tokenProvider,
            onResetConversation: onResetConversation,
            onDeleteData: onDeleteData
        )
        self.network = NetworkManager(
            decoder: Self.decoder,
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
                    headers: self.headers(token: token)
                )
            }
        }
    }

    package func fetchData(_ url: URL) async throws(ChatServiceError) -> Data {
        // Unauthenticated — no bearer token is attached.
        try await self.mappingErrors {
            try await self.network.data(from: url)
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
                try await self.network.get(url: url, headers: self.headers(token: token))
            }
        }
    }

    package func sendMessage(
        _ text: String,
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        let payload = SendMessageRequest(
            message: .init(parts: [.text(text)]),
            context: page.map { .init(page: $0) }
        )

        let (stream, continuation) = AsyncThrowingStream<StreamEvent, any Error>.makeStream()

        let task = Task {
            do {
                // Session bound — a 401 means the conversation expired, surface it.
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    var headers = self.headers(token: token)
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
                        continuation.yield(event)
                        // `.done` is terminal per the SSE contract, deliver it and close stream.
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
}

private extension ChatService {

    /// Messages per history page
    private static let historyPageLimit = 100

    func headers(token: String) -> [String: String] {
        var headers = ["Authorization": "Bearer \(token)"]
        if let sdkVersion = self.sdkVersion {
            headers[Self.sdkVersionHeader] = sdkVersion
        }
        if let clientProfile = self.clientProfile {
            headers[Self.clientProfileHeader] = clientProfile.rawValue
        }
        return headers
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

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension ChatService {

    /// Dialoge API endpoints. Paths live here — the host may override `baseURL`.
    enum Endpoint: String {
        case config = "api/v1/chat/config"
        case messages = "api/v1/chat/messages"
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
