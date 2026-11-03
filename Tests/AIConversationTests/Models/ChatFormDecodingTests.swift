//
//  ChatFormDecodingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins the `/config` `forms[]` row and the `GET /api/v1/chat/forms/{form_id}` body against the
/// shapes the Chatbot API documents.
@Suite("Chat forms — decoding against the API contract")
struct ChatFormDecodingTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - ChatFormReference

    @Test("a config form row decodes its id, name and trigger")
    func configFormRow() throws {
        let row = try self.decode(ChatFormReference.self, """
            {
              "trigger": "livechat_waiting",
              "form_id": "livechatWaitingContact",
              "name": "Waiting contact",
              "override_targets": [],
              "submit_actions": []
            }
            """)

        #expect(row.formId == "livechatWaitingContact")
        #expect(row.name == "Waiting contact")
        #expect(row.trigger == .livechatWaiting)
    }

    @Test("a config form row with a null name is unnamed")
    func configFormRowUnnamed() throws {
        let row = try self.decode(
            ChatFormReference.self,
            #"{"form_id":"frm_1","name":null,"trigger":"session_start"}"#
        )

        #expect(row.name == nil)
        #expect(row.trigger == .sessionStart)
    }

    @Test("an unrecognised trigger decodes to .unknown")
    func unknownTrigger() throws {
        let row = try self.decode(
            ChatFormReference.self,
            #"{"form_id":"frm_1","trigger":"some_future_trigger"}"#
        )

        #expect(row.trigger == .unknown)
    }

    @Test("a config form row without a trigger fails to decode")
    func missingTriggerThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ChatFormReference.self, #"{"form_id":"frm_1"}"#)
        }
    }

    // MARK: - ChatFormDefinition

    @Test("a form definition decodes its fields and minimum filled count")
    func formDefinition() throws {
        let definition = try self.decode(ChatFormDefinition.self, """
            {
              "form_id": "frm_1",
              "name": "Callback",
              "confirmation_text": "Thanks, we will call you back.",
              "fields": [
                { "key": "name", "label": "Your name" },
                { "key": "phone", "label": "Phone", "type": "tel" }
              ],
              "min_filled_fields": 1
            }
            """)

        #expect(definition.formId == "frm_1")
        #expect(definition.name == "Callback")
        #expect(definition.confirmationText == "Thanks, we will call you back.")
        #expect(definition.fields.map(\.key) == ["name", "phone"])
        #expect(definition.minFilledFields == 1)
    }

    @Test("a form definition with a null name is unnamed and has no confirmation copy")
    func formDefinitionUnnamed() throws {
        let definition = try self.decode(
            ChatFormDefinition.self,
            #"{"form_id":"frm_1","name":null,"fields":[],"min_filled_fields":0}"#
        )

        #expect(definition.name == nil)
        #expect(definition.confirmationText == nil)
    }

    @Test("a form definition without fields fails to decode")
    func formDefinitionWithoutFieldsThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ChatFormDefinition.self, #"{"form_id":"frm_1","name":null,"min_filled_fields":0}"#)
        }
    }

    // MARK: - Fixtures

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try self.decoder.decode(type, from: Data(json.utf8))
    }
}
