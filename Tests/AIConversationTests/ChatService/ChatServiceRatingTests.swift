//
//  ChatServiceRatingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — conversation rating on the wire")
struct ChatServiceRatingTests {

    @Test("POST /rate sends rating and bearer token, and accepts an empty 200")
    func ratesSuccessfully() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data())
        ])

        try await sut.rateConversation(RateConversationRequest(rating: 5, feedback: "Great"))

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/rate")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        #expect(json["rating"] as? Int == 5)
        #expect(json["feedback"] as? String == "Great")
    }

    @Test("blank feedback is omitted from the wire body")
    func blankFeedbackOmitted() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data())
        ])

        try await sut.rateConversation(RateConversationRequest(rating: 4, feedback: "   "))

        let json = try #require(script.requests.first?.json)
        #expect(json["rating"] as? Int == 4)
        #expect(json["feedback"] == nil)
    }

    @Test("a 401 on /rate surfaces as sessionExpired")
    func unauthorizedSurfacesExpiry() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])

        await #expect {
            try await sut.rateConversation(RateConversationRequest(rating: 3, feedback: nil))
        } throws: { error in
            if case ChatServiceError.sessionExpired = error { true } else { false }
        }
    }
}
