//
//  ChatServiceTokenRotationTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// End-to-end over a stubbed `URLSession`: the API answers the first turn with `done` carrying a
/// conversation-bound `visitor_token`, and the service must send the *second* turn with that
/// token — not the host-minted one — so both turns land on the same thread.
@Suite("ChatService — done.visitor_token rotation")
struct ChatServiceTokenRotationTests {

    @Test("the token from done.visitor_token is used on the next send")
    func rotatedTokenUsedOnNextSend() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(hostToken: "host-token", responses: [
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message),"visitor_token":"bound-token"}"#),
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message)}"#)
        ])

        try await ChatServiceFixtures.drain(sut.sendMessage("first", page: nil))
        try await ChatServiceFixtures.drain(sut.sendMessage("second", page: nil))

        #expect(script.requests.map { $0.header("Authorization") } == ["Bearer host-token", "Bearer bound-token"])
    }

    @Test("a done without visitor_token leaves the current token in place")
    func absentTokenKeepsCurrent() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(hostToken: "host-token", responses: [
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message)}"#),
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message)}"#)
        ])

        try await ChatServiceFixtures.drain(sut.sendMessage("first", page: nil))
        try await ChatServiceFixtures.drain(sut.sendMessage("second", page: nil))

        #expect(script.requests.map { $0.header("Authorization") } == ["Bearer host-token", "Bearer host-token"])
    }

    @Test("the rotated token is adopted before the done event reaches the consumer")
    func adoptedBeforeYield() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(hostToken: "host-token", responses: [
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message),"visitor_token":"bound-token"}"#),
            ChatServiceFixtures.sse(done: #"{"message":\#(ChatServiceFixtures.message)}"#)
        ])

        // Fire the second send the moment `done` is observed, mirroring a provider that
        // reconciles and lets the user type again immediately.
        for try await event in sut.sendMessage("first", page: nil) {
            if case .done = event {
                try await ChatServiceFixtures.drain(sut.sendMessage("second", page: nil))
            }
        }

        #expect(script.requests.map { $0.header("Authorization") } == ["Bearer host-token", "Bearer bound-token"])
    }
}

// MARK: - Shared fixtures

/// A `ChatService` over `ScriptedURLProtocol`, plus the SSE scaffolding the service suites share.
enum ChatServiceFixtures {

    static let baseURL = URL(string: "https://test.example")!

    static func makeSUT(
        hostToken: String = "host-token",
        responses: [ScriptedURLProtocol.Response]
    ) -> (service: ChatService, script: ScriptedURLProtocol.Script) {
        let (script, session) = ScriptedURLProtocol.make(responses: responses)
        let service = ChatService(
            tokenProvider: { hostToken },
            onResetConversation: { hostToken },
            onDeleteData: {},
            baseURL: Self.baseURL,
            session: session
        )
        return (service, script)
    }

    static func drain(_ stream: AsyncThrowingStream<StreamEvent, any Error>) async throws {
        for try await _ in stream {}
    }

    static let message = #"""
        {"message_id":"m_1","role":"assistant","parts":[],"created_at":"2026-01-01T00:00:00Z"}
        """#

    /// One completed turn: a `connected` status followed by `done` with `data` as its payload.
    static func done(_ data: String = #"{"message":\#(Self.message)}"#) -> ScriptedURLProtocol.Response {
        Self.sse(done: data)
    }

    static func sse(done data: String) -> ScriptedURLProtocol.Response {
        .sse("event: status\ndata: {\"status\":\"connected\"}\n\nevent: done\ndata: \(data)\n\n")
    }
}
