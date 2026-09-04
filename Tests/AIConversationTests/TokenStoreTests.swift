//
//  TokenStoreTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-05.
//

import Foundation
import Testing
@testable import AIConversationCore

@Suite("TokenStore — session token lifecycle")
struct TokenStoreTests {

    // MARK: - Caching

    @Test("Token is fetched on first use only — subsequent calls reuse it")
    func firstUseFetchesOnce() async throws {
        let (sut, hooks) = makeSUT()

        let first = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        let second = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }

        #expect(first == "token-1")
        #expect(second == "token-1")
        #expect(await hooks.providerCalls == 1)
    }

    @Test("Concurrent first requests share a single provider fetch")
    func concurrentFirstRequestsShareFetch() async throws {
        let (sut, hooks) = makeSUT()

        async let first = sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        async let second = sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        let tokens = try await [first, second]

        #expect(tokens.allSatisfy { $0 == "token-1" })
        #expect(await hooks.providerCalls == 1)
    }

    // MARK: - 401 policies

    @Test("retryOnce recovers: 401 refreshes the token and retries the operation")
    func retryOnceRecoversOn401() async throws {
        let (sut, hooks) = makeSUT()

        // The store hands the operation token-1 first and token-2 on the retry —
        // the token itself marks the attempt.
        let result = try await sut.retrieve(onAuthFailure: .retryOnce) { token in
            if token == "token-1" { throw NetworkError.http(.unauthorized) }
            return token
        }

        #expect(result == "token-2")
        #expect(await hooks.providerCalls == 2)
    }

    @Test("retryOnce: a second 401 escapes raw — no retry loop")
    func retryOnceSecondFailureEscapesRaw() async throws {
        let (sut, hooks) = makeSUT()

        do {
            _ = try await sut.retrieve(onAuthFailure: .retryOnce) { (_: String) -> String in
                throw NetworkError.http(.unauthorized)
            }
            Issue.record("Expected unauthorized to escape")
        } catch NetworkError.http(.unauthorized) {
            // expected — escaped untranslated
        }

        #expect(await hooks.providerCalls == 2)
    }

    @Test("surfaceExpiry rethrows the 401 and warms a fresh token for the next call")
    func surfaceExpiryRethrowsAndWarms() async throws {
        let (sut, hooks) = makeSUT()

        do {
            _ = try await sut.retrieve(onAuthFailure: .surfaceExpiry) { (_: String) -> String in
                throw NetworkError.http(.unauthorized)
            }
            Issue.record("Expected unauthorized to escape")
        } catch NetworkError.http(.unauthorized) {
            // expected — session expiry surfaced to the caller
        }

        // Warm-up already fetched the replacement; the next call reuses it.
        let next = try await sut.retrieve(onAuthFailure: .surfaceExpiry) { $0 }
        #expect(next == "token-2")
        #expect(await hooks.providerCalls == 2)
    }

    @Test("surfaceExpiry: a failing warm-up does not mask the session expiry")
    func surfaceExpiryWarmupFailureDoesNotMask() async throws {
        let (sut, hooks) = makeSUT()
        await hooks.failProviderAfterFirstCall()

        do {
            _ = try await sut.retrieve(onAuthFailure: .surfaceExpiry) { (_: String) -> String in
                throw NetworkError.http(.unauthorized)
            }
            Issue.record("Expected unauthorized to escape")
        } catch NetworkError.http(.unauthorized) {
            // expected — provider failure during warm-up stays invisible
        }

        #expect(await hooks.providerCalls == 2)
    }

    // MARK: - Lifecycle

    @Test("reset invalidates the held token and adopts the reset hook's token")
    func resetRotatesToken() async throws {
        let (sut, hooks) = makeSUT()

        let before = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        try await sut.reset()
        let after = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }

        #expect(before == "token-1")
        #expect(after == "reset-1")
        #expect(await hooks.providerCalls == 1)
        #expect(await hooks.resetCalls == 1)
    }

    @Test("delete drops the token on success — next call starts a fresh session")
    func deleteDropsTokenOnSuccess() async throws {
        let (sut, hooks) = makeSUT()

        let before = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        try await sut.delete()
        let after = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }

        #expect(before == "token-1")
        #expect(after == "token-2")
        #expect(await hooks.deleteCalls == 1)
        #expect(await hooks.providerCalls == 2)
    }

    @Test("a failed delete leaves the live session and its token intact")
    func deleteFailureKeepsSession() async throws {
        let (sut, hooks) = makeSUT()
        await hooks.failDelete()

        let before = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }

        do {
            try await sut.delete()
            Issue.record("Expected delete to throw")
        } catch HookError.deleteFailed {
            // expected
        }

        let after = try await sut.retrieve(onAuthFailure: .retryOnce) { $0 }
        #expect(before == "token-1")
        #expect(after == "token-1")
        #expect(await hooks.providerCalls == 1)
    }

    // MARK: - SUT

    private func makeSUT() -> (TokenStore, Hooks) {
        let hooks = Hooks()
        let sut = TokenStore(
            tokenProvider: { try await hooks.provide() },
            onResetConversation: { await hooks.reset() },
            onDeleteData: { try await hooks.delete() }
        )
        return (sut, hooks)
    }
}

// MARK: - Test fixtures

private enum HookError: Error {
    case providerDown
    case deleteFailed
}

/// Records hook invocations and returns sequential tokens
/// (`token-1`, `token-2`, … / `reset-1`, …).
private actor Hooks {

    private(set) var providerCalls = 0
    private(set) var resetCalls = 0
    private(set) var deleteCalls = 0

    private var providerFailsAfterFirstCall = false
    private var deleteFails = false

    func provide() throws -> String {
        self.providerCalls += 1
        if self.providerFailsAfterFirstCall && self.providerCalls > 1 {
            throw HookError.providerDown
        }
        return "token-\(self.providerCalls)"
    }

    func reset() -> String {
        self.resetCalls += 1
        return "reset-\(self.resetCalls)"
    }

    func delete() throws {
        self.deleteCalls += 1
        if self.deleteFails { throw HookError.deleteFailed }
    }

    func failProviderAfterFirstCall() {
        self.providerFailsAfterFirstCall = true
    }

    func failDelete() {
        self.deleteFails = true
    }
}
