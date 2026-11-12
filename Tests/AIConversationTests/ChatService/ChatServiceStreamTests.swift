//
//  ChatServiceStreamTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins what the message stream yields for parts the SDK can't read. Responses come from
/// `ScriptedURLProtocol`; no server is involved.
@Suite("ChatService — message stream")
struct ChatServiceStreamTests {

    @Test("a malformed table is skipped, and the rest of the reply streams through to done")
    func malformedPartKeepsTheStream() async throws {
        let table = #"{"type":"table","part_id":"t_1","columns":[{"header":"Size"}]}"#
        let text = #"{"type":"rich_text","part_id":"p_2","blocks":[]}"#
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [Self.sse([
            ("part_delta", #"{"part_id":"t_1","delta":{"action":"start_part","part_type":"table","columns":[]}}"#),
            ("part", #"{"part":\#(table)}"#),
            ("part", #"{"part":\#(text)}"#),
            ("done", #"{"message":{"message_id":"m_1","role":"assistant","parts":[\#(table),\#(text)],"created_at":"2026-01-01T00:00:00Z"}}"#)
        ])])

        var events: [StreamEvent] = []
        for try await event in sut.sendMessage("sizes?", attachments: [], page: nil) {
            events.append(event)
        }

        let reply = Part.richText(.init(partId: "p_2", blocks: []))
        #expect(events == [
            .delta(partId: "t_1", .unknown),
            .part(.unknown),
            .part(reply),
            .done(Message(
                messageId: "m_1",
                role: .assistant,
                agent: nil,
                parts: [.unknown, reply],
                createdAt: "2026-01-01T00:00:00Z"
            ))
        ])
    }
}

private extension ChatServiceStreamTests {

    /// An SSE body with one frame per `(event, data)` pair.
    static func sse(_ frames: [(event: String, data: String)]) -> ScriptedURLProtocol.Response {
        .sse(frames.map { "event: \($0.event)\ndata: \($0.data)\n\n" }.joined())
    }
}
