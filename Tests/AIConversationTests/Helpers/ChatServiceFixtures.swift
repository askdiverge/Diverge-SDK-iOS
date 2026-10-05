//
//  ChatServiceFixtures.swift
//  AIConversationTests
//

import Foundation
@testable import AIConversationEngine

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
            session: session,
            sdkVersion: "9.8.7",
            clientProfiles: [.productRecommendation]
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
