//
//  ChatServiceLivechatFeedbackTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — livechat CSAT on the wire")
struct ChatServiceLivechatFeedbackTests {

    private static let okJSON = Data(#"""
    {
      "livechat_session_id": "lc_1",
      "environment": "test",
      "status": "submitted",
      "rating": 5,
      "feedback": "Great",
      "submitted_at": "2026-01-01T00:00:00Z"
    }
    """#.utf8)

    @Test("POST /livechat/feedback sends bearer + body and decodes the response")
    func submitsSuccessfully() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.okJSON)
        ])

        let response = try await sut.submitLivechatFeedback(
            RateConversationRequest(rating: 5, feedback: "Great")
        )

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/livechat/feedback")
        #expect(request.request.httpMethod == "POST")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        #expect(json["rating"] as? Int == 5)
        #expect(json["feedback"] as? String == "Great")
        #expect(response.livechatSessionId == "lc_1")
        #expect(response.status == "submitted")
        #expect(response.rating == 5)
    }

    @Test("401 surfaces as sessionExpired")
    func unauthorized() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])
        do {
            _ = try await sut.submitLivechatFeedback(RateConversationRequest(rating: 3))
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }
    }

    @Test("409 surfaces as conflict")
    func conflict() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 409, body: Data(#"{"error":{"code":"conflict","message":"already"}}"#.utf8))
        ])
        do {
            _ = try await sut.submitLivechatFeedback(RateConversationRequest(rating: 4))
            Issue.record("expected conflict")
        } catch ChatServiceError.conflict {
            // expected
        } catch {
            Issue.record("expected conflict, got \(error)")
        }
    }
}

@Suite("LivechatFeedbackResponse decode")
struct LivechatFeedbackResponseTests {

    @Test("lenient decode tolerates missing optional fields")
    func lenient() throws {
        let data = Data(#"{"status":"submitted"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(LivechatFeedbackResponse.self, from: data)
        #expect(response.status == "submitted")
        #expect(response.livechatSessionId == nil)
    }
}
