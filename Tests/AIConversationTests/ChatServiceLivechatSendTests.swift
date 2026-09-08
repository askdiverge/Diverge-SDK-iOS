//
//  ChatServiceLivechatSendTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — livechat send with attachments")
struct ChatServiceLivechatSendTests {

    private static let okEnvelope = Data(#"""
    {
      "message": {
        "message_id": "lc_1",
        "role": "user",
        "parts": [{"type":"unknown_part"}],
        "created_at": "2026-01-01T00:00:00Z",
        "sequence_number": 1
      }
    }
    """#.utf8)

    @Test("POST /livechat/messages sends bearer and an image part with verbatim payload")
    func sendsImagePart() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.okEnvelope)
        ])
        let image = OutgoingAttachment(kind: .image, data: "aGVsbG8=", mime: "image/jpeg")

        _ = try await sut.sendLivechatMessage("see this", attachments: [image], page: nil)

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/livechat/messages")
        #expect(request.request.httpMethod == "POST")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        let message = try #require(json["message"] as? [String: Any])
        let parts = try #require(message["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "see this")
        #expect(parts[1]["type"] as? String == "image")
        #expect(parts[1]["data"] as? String == "aGVsbG8=")
        #expect(parts[1]["mime"] as? String == "image/jpeg")
    }

    @Test("attachment-only livechat send omits the text part")
    func attachmentOnly() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.okEnvelope)
        ])
        let image = OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg")

        _ = try await sut.sendLivechatMessage("", attachments: [image], page: nil)

        let parts = try #require(
            (script.requests.first?.json?["message"] as? [String: Any])?["parts"] as? [[String: Any]]
        )
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image")
    }
}
