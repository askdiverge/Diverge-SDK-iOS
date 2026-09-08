//
//  ChatServiceFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — waiting form on the wire")
struct ChatServiceFormTests {

    private static let formJSON = Data(#"""
    {
      "form_id": "livechatWaitingContact",
      "environment": "test",
      "name": "Waiting contact",
      "trigger": "livechat_waiting",
      "trigger_prompt": null,
      "fields": [
        { "key": "email", "label": "Email", "type": "email", "required": false },
        { "key": "order_number", "label": "Order", "type": "text", "required": false }
      ],
      "min_filled_fields": 1,
      "override_targets": [],
      "submit_actions": []
    }
    """#.utf8)

    private static let sessionJSON = Data(#"""
    {
      "values": [
        { "key": "email", "label": "Email", "type": "email", "value": "a@b.com", "updated_at": "2026-01-01T00:00:00Z" }
      ]
    }
    """#.utf8)

    @Test("GET /forms/{id} and GET /session send bearer")
    func fetchFormAndSession() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.formJSON),
            .init(status: 200, body: Self.sessionJSON),
        ])

        let form = try await sut.fetchForm(id: "livechatWaitingContact")
        #expect(form.formId == "livechatWaitingContact")
        #expect(form.fields.count == 2)
        #expect(form.minFilledFields == 1)

        let session = try await sut.fetchSession()
        #expect(session.values.count == 1)
        #expect(session.values[0].key == "email")

        #expect(script.requests.count == 2)
        #expect(script.requests[0].url?.path() == "/api/v1/chat/forms/livechatWaitingContact")
        #expect(script.requests[0].request.httpMethod == "GET")
        #expect(script.requests[0].header("Authorization") == "Bearer host-token")
        #expect(script.requests[1].url?.path() == "/api/v1/chat/session")
    }

    @Test("PATCH /forms/{id}/values keeps field keys verbatim and sends bearer")
    func patchValues() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.sessionJSON),
        ])

        _ = try await sut.patchFormValues(
            formId: "livechatWaitingContact",
            values: ["email": "a@b.com", "orderNumber": "ORDER-1"]
        )

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/forms/livechatWaitingContact/values")
        #expect(request.request.httpMethod == "PATCH")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        let values = try #require(json["values"] as? [String: Any])
        #expect(values["email"] as? String == "a@b.com")
        #expect(values["orderNumber"] as? String == "ORDER-1")
    }

    @Test("401 surfaces as sessionExpired; 409 as conflict")
    func authAndConflict() async throws {
        let (sut401, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])
        do {
            _ = try await sut401.fetchForm(id: "x")
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }

        let (sut409, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 409, body: Data(#"{"error":{"code":"conflict"}}"#.utf8))
        ])
        do {
            _ = try await sut409.patchFormValues(formId: "x", values: ["email": "a@b.com"])
            Issue.record("expected conflict")
        } catch ChatServiceError.conflict {
            // expected
        } catch {
            Issue.record("expected conflict, got \(error)")
        }
    }
}
