//
//  ChatServiceExportTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — GDPR export on the wire")
struct ChatServiceExportTests {

    private static let exportJSON = Data(
        #"{"generated_at":"2026-01-01T00:00:00Z","chatbot_id":"bot","visitor_id":"v","session":{"values":[]},"conversations":[],"livechat_sessions":[],"attachments":[],"support_tickets":[],"webhook_events":[]}"#
            .utf8
    )

    @Test("GET /export sends bearer and returns the body unchanged")
    func exportsSuccessfully() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.exportJSON)
        ])

        let data = try await sut.exportMyData()

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/export")
        #expect(request.request.httpMethod == "GET")
        #expect(request.header("Authorization") == "Bearer host-token")
        #expect(data == Self.exportJSON)
    }

    @Test("export success leaves the bearer usable for a later call")
    func tokenKeptAfterExport() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.exportJSON),
            .init(status: 200, body: Data())
        ])

        _ = try await sut.exportMyData()
        try await sut.rateConversation(RateConversationRequest(rating: 5))

        #expect(script.requests.map { $0.header("Authorization") } == [
            "Bearer host-token",
            "Bearer host-token"
        ])
    }

    @Test("a 401 on /export surfaces as sessionExpired")
    func unauthorizedSurfacesExpiry() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])

        do {
            _ = try await sut.exportMyData()
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }
    }

    @Test("500 on /export surfaces as a transport error")
    func serverErrorIsTransport() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 500, body: Data("{\"error\":\"nope\"}".utf8))
        ])

        do {
            _ = try await sut.exportMyData()
            Issue.record("expected a transport error")
        } catch ChatServiceError.transport(.http(.unhandled(let code))) {
            #expect(code == 500)
        } catch {
            Issue.record("expected transport(.http(.unhandled)), got \(error)")
        }
    }
}
