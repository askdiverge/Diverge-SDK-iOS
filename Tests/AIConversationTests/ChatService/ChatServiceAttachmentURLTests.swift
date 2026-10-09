//
//  ChatServiceAttachmentURLTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins that attachment URLs the API returns as bare paths resolve against the service's base
/// URL. Responses come from `ScriptedURLProtocol`; no server is involved.
@Suite("ChatService — attachment URLs")
struct ChatServiceAttachmentURLTests {

    @Test("a file part with a bare path resolves against the API base URL")
    func relativeFileURLResolves() async throws {
        let body = Data(#"""
        {
          "messages": [{
            "message_id": "m_1",
            "role": "agent",
            "parts": [{
              "type": "file",
              "filename": "receipt.pdf",
              "url": "/api/v1/chat/livechat/attachments/att_1"
            }],
            "created_at": "2026-01-01T00:00:00Z"
          }],
          "next_cursor": null
        }
        """#.utf8)
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(body: body)])

        let page = try await sut.fetchHistory(cursor: nil)

        let part = try #require(page.messages.first?.parts.first)
        guard case .file(let file) = part else {
            Issue.record("expected a file part, got \(part)")
            return
        }
        #expect(file.url == URL(string: "https://test.example/api/v1/chat/livechat/attachments/att_1"))
    }

    @Test("an agent avatar with a bare path resolves against the API base URL")
    func relativeAvatarURLResolves() async throws {
        let body = Data(#"""
        {
          "messages": [{
            "message_id": "m_1",
            "role": "agent",
            "agent": {
              "agent_id": "00000000-0000-4000-8000-0000000000a1",
              "display_name": "Alice",
              "avatar_url": "/api/v1/chat/livechat/agents/a1/avatar.png"
            },
            "parts": [],
            "created_at": "2026-01-01T00:00:00Z"
          }],
          "next_cursor": null
        }
        """#.utf8)
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(body: body)])

        let page = try await sut.fetchHistory(cursor: nil)

        let agent = try #require(page.messages.first?.agent)
        #expect(agent.avatarUrl == URL(string: "https://test.example/api/v1/chat/livechat/agents/a1/avatar.png"))
    }
}
