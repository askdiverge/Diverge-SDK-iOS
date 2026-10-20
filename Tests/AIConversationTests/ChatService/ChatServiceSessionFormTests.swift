//
//  ChatServiceSessionFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — session values and form PATCH on the wire")
struct ChatServiceSessionFormTests {

    @Test("GET /session sends bearer and decodes values")
    func fetchSession() async throws {
        let body = Data(#"""
        {
          "values": [
            { "key": "email", "value": "shopper@example.com", "label": "Email" },
            { "key": "order_number", "value": "42" }
          ],
          "metadata": { "ignored": true }
        }
        """#.utf8)
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: body)])

        let session = try await sut.fetchSession()
        #expect(session.values == [
            ChatSessionValue(key: "email", value: "shopper@example.com"),
            ChatSessionValue(key: "order_number", value: "42")
        ])
        #expect(script.requests.count == 1)
        #expect(script.requests[0].url?.path() == "/api/v1/chat/session")
        #expect(script.requests[0].request.httpMethod == "GET")
        #expect(script.requests[0].header("Authorization") == "Bearer host-token")
    }

    @Test("GET /session fails to decode a response without values")
    func sessionWithoutValuesFails() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data(#"{"metadata":{}}"#.utf8))])

        await #expect {
            _ = try await sut.fetchSession()
        } throws: { error in
            if case ChatServiceError.transport(.decoding) = error { true } else { false }
        }
    }

    @Test("PATCH /forms/{id}/values keeps field keys verbatim and returns the session")
    func patchFormValues() async throws {
        let body = Data(#"""
        { "values": [{ "key": "orderNumber", "value": "42" }] }
        """#.utf8)
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: body)])

        let session = try await sut.patchFormValues(
            formId: "livechatWaitingContact",
            values: ["orderNumber": "42", "phone_number": "+45 12 34"]
        )
        #expect(session.values == [ChatSessionValue(key: "orderNumber", value: "42")])

        #expect(script.requests.count == 1)
        let recorded = script.requests[0]
        #expect(recorded.url?.path() == "/api/v1/chat/forms/livechatWaitingContact/values")
        #expect(recorded.request.httpMethod == "PATCH")
        #expect(recorded.header("Authorization") == "Bearer host-token")
        let json = try #require(recorded.json)
        #expect(json["values"] as? [String: String] == ["orderNumber": "42", "phone_number": "+45 12 34"])
    }

    @Test("a form id is sent as a single path segment on PATCH")
    func patchFormIDIsOneSegment() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data(#"{"values":[]}"#.utf8))])

        _ = try await sut.patchFormValues(formId: "a/../b", values: ["email": "a@b.c"])

        #expect(script.requests.first?.url?.path() == "/api/v1/chat/forms/a%2F..%2Fb/values")
    }

    @Test("a 409 on PATCH (no longer waiting) surfaces as conflict, and a 404 as notFound")
    func patchConflictAndNotFound() async {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409), .init(status: 404)])

        await #expect {
            _ = try await sut.patchFormValues(formId: "livechatWaitingContact", values: ["email": "a@b.co"])
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
        await #expect {
            _ = try await sut.patchFormValues(formId: "gone", values: ["email": "a@b.co"])
        } throws: { error in
            if case ChatServiceError.notFound = error { true } else { false }
        }
    }

    @Test("a 422 on PATCH surfaces as validation")
    func patchValidation() async throws {
        let body = Data(#"""
        {
          "error": {
            "code": "validation_error",
            "message": "Please fix the highlighted fields.",
            "params": [
              { "field": "values.email", "message": "value must be a valid email address" }
            ]
          }
        }
        """#.utf8)
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 422, body: body)])
        do {
            _ = try await sut.patchFormValues(formId: "livechatWaitingContact", values: ["email": "nope"])
            Issue.record("expected validation")
        } catch ChatServiceError.validation(let message, let params) {
            #expect(message == "Please fix the highlighted fields.")
            #expect(params == [ValidationError(field: "values.email", message: "value must be a valid email address")])
        } catch {
            Issue.record("expected validation, got \(error)")
        }
    }
}
