//
//  ChatServiceFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — form definition on the wire")
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

    @Test("GET /forms/{id} sends bearer and decodes the definition")
    func fetchForm() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.formJSON)
        ])

        let form = try await sut.fetchForm(id: "livechatWaitingContact")
        #expect(form.formId == "livechatWaitingContact")
        #expect(form.fields.count == 2)
        #expect(form.minFilledFields == 1)

        #expect(script.requests.count == 1)
        #expect(script.requests[0].url?.path() == "/api/v1/chat/forms/livechatWaitingContact")
        #expect(script.requests[0].request.httpMethod == "GET")
        #expect(script.requests[0].header("Authorization") == "Bearer host-token")
    }

    @Test("a form id is sent as a single path segment")
    func formIDIsOneSegment() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.formJSON)
        ])

        _ = try await sut.fetchForm(id: "a/../b")

        #expect(script.requests.first?.url?.path() == "/api/v1/chat/forms/a%2F..%2Fb")
    }

    @Test("a 401 on GET /forms is retried once with a fresh token")
    func unauthorizedIsRetriedOnce() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data()),
            .init(status: 200, body: Self.formJSON)
        ])

        let form = try await sut.fetchForm(id: "livechatWaitingContact")

        #expect(form.formId == "livechatWaitingContact")
        #expect(script.requests.count == 2)
    }
}
