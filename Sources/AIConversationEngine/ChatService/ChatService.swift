//
//  ChatService.swift
//  AIConversationEngine
//
//  Created by Daniel Wennberg on 2026-06-04.
//

import Foundation
import AIConversationCore

/// Concrete SDK facade over the Dialoge chat API.
package final class ChatService: Sendable {

    /// Live production API — the default unless `baseURL` is overridden.
    package static let productionBaseURL = URL(string: "https://api.dialogintelligens.dk")!
    /// Shared development API — same contract as production, for integrating ahead of a release.
    package static let developmentBaseURL = URL(string: "https://dev.api.dialogintelligens.dk")!

    /// Which client implementation is calling. Together with ``sdkVersionHeader`` this identifies
    /// one release of one SDK, since the iOS, Android and web SDKs version independently.
    package static let sdkPlatformHeader = "X-Diverge-SDK-Platform"
    /// The value this repository sends for ``sdkPlatformHeader``.
    package static let sdkPlatform = "ios"
    /// SemVer of the SDK release, from `VERSION`.
    package static let sdkVersionHeader = "X-Diverge-SDK-Version"
    /// The features the build requests, as a comma-separated list; see ``ClientProfile``.
    package static let clientProfileHeader = "X-Diverge-Client-Profile"

    let network: NetworkManager
    let tokenStore: TokenStore
    let baseURL: URL
    let sdkVersion: String
    let clientProfiles: [ClientProfile]

    /// - Parameters:
    ///   - baseURL: Chatbot API host — one of the Diverge deployments the public surface exposes
    ///     as ``DivergeAPI/Environment``.
    ///   - sdkVersion: SemVer of the SDK release, sent as ``sdkVersionHeader`` on every
    ///     authenticated call alongside ``sdkPlatform``.
    ///   - clientProfiles: Every feature this build requests, sent as ``clientProfileHeader``.
    ///     The backend grants the subset the caller is eligible for.
    package init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        onResetConversation: @escaping @Sendable () async throws -> String,
        onDeleteData: @escaping @Sendable () async throws -> Void,
        baseURL: URL = ChatService.productionBaseURL,
        session: URLSession = ChatService.makeSession(),
        sdkVersion: String,
        clientProfiles: [ClientProfile]
    ) {
        self.baseURL = baseURL
        self.sdkVersion = sdkVersion
        self.clientProfiles = clientProfiles
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
                    headers: self.headers(token: token)
                )
            }
        }
    }

    package func fetchData(_ url: URL) async throws(ChatServiceError) -> Data {
        // Inline data URLs (visitor uploads echoed by the API) decode without a network hop.
        if url.scheme?.lowercased() == "data" {
            guard let data = AttachmentURL.payload(ofDataURL: url) else {
                throw .transport(.decoding(.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "The data: URL payload does not decode."
                ))))
            }
            return data
        }
        // Unauthenticated — no bearer token is attached.
        return try await self.mappingErrors {
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
        attachments: [OutgoingAttachment],
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        let payload = SendMessageRequest(
            message: .init(parts: SendMessageRequest.Part.make(text: text, attachments: attachments)),
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
                let failure = ChatServiceError(error)
                if case .transport(.http(.unhandled(status: 409, body: _))) = failure {
                    continuation.finish(throwing: ChatServiceError.conflict)
                } else {
                    continuation.finish(throwing: failure)
                }
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

    package func submitAction(
        _ request: SubmitActionRequest
    ) async throws(ChatServiceError) -> SubmitActionResponse {
        do {
            return try await self.mappingErrors {
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    try await self.network.post(
                        url: self.url(for: .actions),
                        payload: request,
                        headers: self.headers(token: token)
                    )
                }
            }
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        }
    }

    package func fetchForm(id: String) async throws(ChatServiceError) -> ChatFormDefinition {
        // Fetched while a conversation is on screen, so a 401 ends that session, as on `/actions`.
        do {
            return try await self.mappingErrors {
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    try await self.network.get(
                        url: self.url(for: .forms).appending(component: id),
                        headers: self.headers(token: token)
                    )
                }
            }
        } catch .transport(.http(.unhandled(status: 404, body: _))) {
            throw .notFound
        }
    }

    package func fetchSession() async throws(ChatServiceError) -> ChatSessionState {
        try await self.mappingErrors {
            try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                try await self.network.get(
                    url: self.url(for: .session),
                    headers: self.headers(token: token)
                )
            }
        }
    }

    package func patchFormValues(
        formId: String,
        values: [String: String]
    ) async throws(ChatServiceError) -> ChatSessionState {
        do {
            return try await self.mappingErrors {
                try await self.tokenStore.retrieve(onAuthFailure: .surfaceExpiry) { token in
                    try await self.network.patch(
                        url: self.url(for: .forms).appending(component: formId).appending(component: "values"),
                        payload: ChatFormValuesPatchRequest(values: values),
                        headers: self.headers(token: token)
                    )
                }
            }
        } catch .transport(.http(.unhandled(status: 409, body: _))) {
            throw .conflict
        } catch .transport(.http(.unhandled(status: 404, body: _))) {
            throw .notFound
        }
    }
}
