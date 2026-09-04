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

    private let network: NetworkManager
    private let tokenStore: TokenStore

    package init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        onResetConversation: @escaping @Sendable () async throws -> String,
        onDeleteData: @escaping @Sendable () async throws -> Void,
        session: URLSession = ChatService.makeSession()
    ) {
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
                    url: Endpoint.config.url,
                    headers: Self.headers(token: token)
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
        let url = Endpoint.messages.url.appending(queryItems: queryItems)
        // Session bound — a 401 means the conversation expired, surface it.
        return try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(url: url, headers: Self.headers(token: token))
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
                    var headers = Self.headers(token: token)
                    headers["Accept"] = "text/event-stream"

                    let events: AsyncThrowingStream<StreamEvent, any Error> = self.network.stream(
                        url: Endpoint.messages.url,
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

    /// Dialoge API endpoints. The base URL and every path the facade talks to
    /// live here — concrete methods reference `Endpoint.<case>.url` only.
    enum Endpoint: String {

        private static let baseURL = URL(string: "https://api.dialogintelligens.dk")!

        case config = "api/v1/chat/config"
        case messages = "api/v1/chat/messages"

        var url: URL {
            Self.baseURL.appending(path: self.rawValue)
        }
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
