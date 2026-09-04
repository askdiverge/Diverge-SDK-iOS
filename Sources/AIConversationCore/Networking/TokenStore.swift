//
//  TokenStore.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-06-04.
//

import Foundation

/// In-memory bearer-token cache and auth-retry policy.
///
/// The host's `tokenProvider` is consulted only when no token is cached or a
/// cached token has been rejected with 401 — never once per request.
package actor TokenStore {

    private let tokenProvider: @Sendable () async throws -> String
    private let onResetConversation: @Sendable () async throws -> String
    private let onDeleteData: @Sendable () async throws -> Void
    private var current: String?
    private var inflight: Task<String, any Error>?
    private var token: String {
        get async throws {
            if let inflight { return try await inflight.value }
            if let current { return current }
            return try await self.fetch(using: self.tokenProvider)
        }
    }

    package init(
        tokenProvider: @escaping @Sendable () async throws -> String,
        onResetConversation: @escaping @Sendable () async throws -> String,
        onDeleteData: @escaping @Sendable () async throws -> Void
    ) {
        self.tokenProvider = tokenProvider
        self.onResetConversation = onResetConversation
        self.onDeleteData = onDeleteData
    }

    /// Runs `operation` with a valid token, applying `policy` on 401.
    /// Errors escape
    package func retrieve<T: Sendable>(
        onAuthFailure policy: AuthFailurePolicy,
        _ operation: @Sendable (_ token: String) async throws -> T
    ) async throws -> T {
        let token = try await self.token
        do {
            return try await operation(token)
        } catch NetworkError.http(.unauthorized) {
            switch policy {
            case .retryOnce:
                return try await operation(try await self.refresh(replacing: token))
            case .surfaceExpiry:
                // Best-effort warm-up — a provider failure does not mask
                // real event, which is that the session expired.
                _ = try? await self.refresh(replacing: token)
                throw NetworkError.http(.unauthorized)
            }
        }
    }

    /// Rotates the session: invalidates the cached token (discarding any
    /// in-flight fetch), then asks the host's reset hook for the fresh-session
    /// token and caches it.
    package func reset() async throws {
        self.invalidate()
        _ = try await self.fetch(using: self.onResetConversation)
    }

    /// Full data wipe via the host's delete hook. State is dropped only on success —
    /// a failed deletion leaves the live session (and its token) intact. No
    /// replacement token is fetched, deletion deliberately ends the session.
    package func delete() async throws {
        try await self.onDeleteData()
        self.invalidate()
    }

    /// Replaces a token rejected with 401. If another caller already refreshed
    /// (the cache no longer holds `stale`), returns the newer token without
    /// consulting the provider — concurrent 401s trigger exactly one fetch.
    private func refresh(replacing stale: String) async throws -> String {
        if let inflight { return try await inflight.value }
        if let current, current != stale { return current }
        self.current = nil
        return try await self.fetch(using: self.tokenProvider)
    }

    /// Discards the cached token and any in-flight fetch..
    private func invalidate() {
        self.inflight?.cancel()
        self.inflight = nil
        self.current = nil
    }

    private func fetch(using provider: @escaping @Sendable () async throws -> String) async throws -> String {
        let task = Task { try await provider() }
        self.inflight = task
        defer {
            // A cancelled fetch was replaced — it must not clear its successor's slot.
            if !task.isCancelled { self.inflight = nil }
        }

        let value = try await task.value
        guard !task.isCancelled else { return value }
        self.current = value
        return value
    }
}

extension TokenStore {

    /// How a 401 error should be handled.
    /// 401 expiry means the current Token is invalid and by extention so is the active session/conversation.
    /// Only calls that are not bound to the current token can retry safely.
    package enum AuthFailurePolicy {

        /// Session-agnostic call,  retry once.
        /// on second 401, transport failure to surface.
        case retryOnce

        /// Session-bound call.
        /// Surface 401 so the caller can react to the session/conversation ending.
        /// pre-emptively get a fresh token so we're primed for the next session (best-effort).
        case surfaceExpiry
    }
}
