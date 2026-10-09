//
//  ChatServiceLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// What the livechat endpoints send and how their responses decode.
@Suite("ChatService — livechat on the wire")
struct ChatServiceLivechatTests {

    @Test("GET /livechat/state decodes the spec example")
    func fetchState() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data("""
        {
          "environment": "live",
          "status": "active",
          "platform": "website",
          "active_agent": {
            "agent_id": "00000000-0000-4000-8000-0000000000a1",
            "display_name": "Alice Jensen",
            "avatar_url": "https://cdn.example.com/agents/alice.png"
          },
          "is_agent_typing": true,
          "language": "english",
          "feedback": { "status": "not_available", "submitted_at": null },
          "updated_at": "2025-06-15T14:31:20Z",
          "agent_joined_at": "2025-06-15T14:31:00Z",
          "closed_at": null,
          "closed_by": null,
          "closed_by_agent_id": null,
          "close_reason": null
        }
        """.utf8))])

        let state = try await sut.fetchLivechatState()

        #expect(script.requests.first?.url?.path() == "/api/v1/chat/livechat/state")
        #expect(script.requests.first?.header("Authorization") == "Bearer host-token")
        #expect(state.status == .active)
        #expect(state.activeAgent?.displayName == "Alice Jensen")
        #expect(state.isAgentTyping)
        #expect(state.feedback.status == .notAvailable)
        #expect(state.closedBy == nil)
        #expect(state.stateVersion == nil)
    }

    @Test("a 401 on a livechat call surfaces as session expiry")
    func unauthorizedExpires() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 401)])

        await #expect {
            _ = try await sut.fetchLivechatState()
        } throws: { error in
            if case ChatServiceError.sessionExpired = error { true } else { false }
        }
    }

    @Test("GET /livechat/messages asks for messages after the cursor once it has one")
    func fetchMessagesCursor() async throws {
        let page = Data("""
        {
          "messages": [{
            "message_id": "livechat_msg_2",
            "role": "agent",
            "parts": [],
            "created_at": "2025-06-15T14:31:00Z",
            "sequence_number": 2
          }],
          "has_more": false
        }
        """.utf8)
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: page)])

        let first = try await sut.fetchLivechatMessages(after: nil)
        _ = try await sut.fetchLivechatMessages(after: 2)

        #expect(script.requests[0].url?.path() == "/api/v1/chat/livechat/messages")
        #expect(script.requests[0].url?.query() == nil)
        #expect(script.requests[1].url?.query() == "after_sequence_number=2")
        #expect(ChatService.livechatAfterSequenceQueryItem == "after_sequence_number")
        #expect(first.messages.map(\.sequenceNumber) == [2])
        #expect(first.messages.first?.role == .agent)
    }

    @Test("POST /livechat/handover sends the platform, source and client context, and returns the status")
    func handoverBody() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data(#"{"status":"active"}"#.utf8))])
        let context = LivechatClientContext(
            browser: "Sample",
            browserLanguage: "en-US",
            browserVersion: "1.2.3",
            currentPageUrl: "/orders/123",
            language: "en",
            os: "iOS"
        )

        let status = try await sut.requestLivechatHandover(source: .manualButton, partId: nil, clientContext: context)

        #expect(status == .active)
        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/livechat/handover")
        #expect(request.request.httpMethod == "POST")
        let json = try #require(request.json)
        #expect(json["platform"] as? String == "mobile_app")
        #expect(LivechatHandoverRequest.nativePlatform == "mobile_app")
        #expect(json["source"] as? String == "manual_button")
        #expect(json["part_id"] == nil)
        #expect(json["client_context"] as? [String: String] == [
            "browser": "Sample",
            "browser_language": "en-US",
            "browser_version": "1.2.3",
            "current_page_url": "/orders/123",
            "language": "en",
            "os": "iOS"
        ])
    }

    @Test("a marker handover sends its part_id and omits an absent client context")
    func markerHandoverBody() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data(#"{"status":"waiting"}"#.utf8))])

        _ = try await sut.requestLivechatHandover(source: .assistantMarker, partId: "part_human_1", clientContext: nil)

        let json = try #require(script.requests.first?.json)
        #expect(json["source"] as? String == "assistant_marker")
        #expect(json["part_id"] as? String == "part_human_1")
        #expect(json["client_context"] == nil)
    }

    @Test("a 409 on handover surfaces as conflict")
    func handoverConflict() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409)])

        await #expect {
            try await sut.requestLivechatHandover(source: .manualButton, partId: nil, clientContext: nil)
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
    }

    @Test("POST /livechat/messages sends a text part and returns the nested stored message")
    func sendMessage() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data("""
        {
          "message_id": "top_level_copy",
          "role": "user",
          "parts": [],
          "created_at": "2026-01-01T00:00:00Z",
          "sequence_number": 1,
          "message": {
            "message_id": "lc_1",
            "role": "user",
            "parts": [],
            "created_at": "2026-01-01T00:00:00Z",
            "sequence_number": 1
          },
          "livechat_session": {}
        }
        """.utf8))])

        let stored = try await sut.sendLivechatMessage("Here is my order", page: "/orders/123")

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/livechat/messages")
        #expect(request.request.httpMethod == "POST")
        let json = try #require(request.json)
        let message = try #require(json["message"] as? [String: Any])
        #expect(message["parts"] as? [[String: String]] == [["type": "text", "text": "Here is my order"]])
        #expect(json["context"] as? [String: String] == ["page": "/orders/123"])
        #expect(stored.messageId == "lc_1")
    }

    @Test("a 409 on a livechat send surfaces as conflict")
    func sendConflict() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409)])

        await #expect {
            _ = try await sut.sendLivechatMessage("hi", page: nil)
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
    }

    @Test("a 409 on an assistant send, while an agent session is active, surfaces as conflict")
    func assistantSendConflict() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409)])

        await #expect {
            try await ChatServiceFixtures.drain(sut.sendMessage("hi", page: nil))
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
    }

    @Test("a 409 on close, with no open session, surfaces as conflict")
    func closeConflict() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409)])

        await #expect {
            try await sut.closeLivechat(reason: nil)
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
    }

    @Test("typing and close post their bodies")
    func typingAndClose() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init()])

        try await sut.sendLivechatTyping(isTyping: true)
        try await sut.closeLivechat(reason: "visitor_left")
        try await sut.closeLivechat(reason: nil)

        #expect(script.requests[0].url?.path() == "/api/v1/chat/livechat/typing")
        #expect(script.requests[0].json?["is_typing"] as? Bool == true)
        #expect(script.requests[1].url?.path() == "/api/v1/chat/livechat/close")
        #expect(script.requests[1].json?["reason"] as? String == "visitor_left")
        #expect(script.requests[2].json?.isEmpty == true)
    }
}

@Suite("LivechatClientContext")
struct LivechatClientContextTests {

    @Test("fields are trimmed, blanks dropped, and long values cut to the API limits")
    func clampsFields() {
        let context = LivechatClientContext(
            browser: String(repeating: "b", count: 300),
            browserLanguage: "  da  ",
            currentPageUrl: String(repeating: "p", count: 3000),
            language: "   "
        )

        #expect(context.browser?.count == 255)
        #expect(context.browserLanguage == "da")
        #expect(context.currentPageUrl?.count == 2048)
        #expect(context.language == nil)
    }

    @Test("the native context sends the UI language, page and OS, and leaves the browser fields to browsers")
    func nativeContext() {
        let context = LivechatClientContext.native(page: "/cart", preferredLanguages: ["sv-SE"])

        #expect(context.os == "iOS" || context.os == "macOS")
        #expect(context.browserLanguage == "sv-SE")
        #expect(context.currentPageUrl == "/cart")
        #expect(context.browser == nil)
        #expect(context.browserVersion == nil)
        #expect(context.language == nil)
    }

    @Test("long values are cut in UTF-16 code units, keeping whole characters")
    func clampsInUTF16() throws {
        let context = LivechatClientContext(os: String(repeating: "a", count: 254) + "😀")

        let os = try #require(context.os)
        #expect(os.utf16.count == 254)
        #expect(os.last == "a")
    }
}
