//
//  FormMarkerDecodingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins how the contact-form, support-ticket and custom-form markers decode: every key the
/// contract requires must be present, and a `show_form` may carry its fields empty.
@Suite("Form markers — decoding against the API contract")
struct FormMarkerDecodingTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - show_contact_form

    @Test("a contact form decodes its inline fields in order")
    func contactFormFields() throws {
        let form = try self.decode(ShowContactForm.self, """
            {
              "type": "show_contact_form",
              "part_id": "part_2",
              "fields": [
                { "key": "name", "label": "Your name", "required": true },
                { "key": "email", "label": "Email address", "type": "email", "required": true }
              ]
            }
            """)

        #expect(form.partId == "part_2")
        #expect(form.fields.map(\.key) == ["name", "email"])
        #expect(form.fields.map(\.type) == [.text, .email])
    }

    @Test("a contact form without fields fails to decode")
    func contactFormWithoutFieldsThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ShowContactForm.self, #"{"type":"show_contact_form","part_id":"p_1"}"#)
        }
    }

    @Test("a contact form with a malformed field fails to decode")
    func contactFormMalformedFieldThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(
                ShowContactForm.self,
                #"{"type":"show_contact_form","part_id":"p_1","fields":[{"key":"email","label":null}]}"#
            )
        }
    }

    @Test("a contact form without part_id fails to decode")
    func contactFormWithoutPartIDThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ShowContactForm.self, #"{"type":"show_contact_form","fields":[]}"#)
        }
    }

    // MARK: - show_support_ticket

    @Test("a support ticket without its attachment flags fails to decode")
    func supportTicketWithoutFlagsThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ShowSupportTicket.self, #"{"type":"show_support_ticket","part_id":"p_1","fields":[]}"#)
        }
    }

    @Test("a support ticket decodes its fields and attachment flags")
    func supportTicketFlags() throws {
        let ticket = try self.decode(ShowSupportTicket.self, """
            {
              "type": "show_support_ticket",
              "part_id": "p_1",
              "fields": [{ "key": "message", "label": "Message", "type": "textarea" }],
              "attachments_accepted": false,
              "max_attachment_size_bytes": 5242880
            }
            """)

        #expect(ticket.fields.map(\.key) == ["message"])
        #expect(ticket.attachmentsAccepted == false)
        #expect(ticket.maxAttachmentSizeBytes == 5_242_880)
    }

    // MARK: - show_form

    @Test("a show_form without its name or fields fails to decode")
    func showFormWithoutDefinitionThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ShowForm.self, #"{"type":"show_form","form_id":"frm_1","part_id":"p_1"}"#)
        }
    }

    @Test("a show_form with empty fields decodes, for the client to hydrate")
    func showFormWithEmptyFields() throws {
        let form = try self.decode(
            ShowForm.self,
            #"{"type":"show_form","form_id":"frm_1","part_id":"p_1","name":"Callback","fields":[],"min_filled_fields":0}"#
        )

        #expect(form.partId == "p_1")
        #expect(form.formId == "frm_1")
        #expect(form.confirmationText == nil)
        #expect(form.fields.isEmpty)
    }

    @Test("a show_form name is trimmed, and a blank one decodes as unnamed")
    func showFormNameTrimming() throws {
        let named = try self.decode(
            ShowForm.self,
            #"{"type":"show_form","form_id":"frm_1","part_id":"p_1","name":"  Waiting contact \n","fields":[],"min_filled_fields":0}"#
        )
        let blank = try self.decode(
            ShowForm.self,
            #"{"type":"show_form","form_id":"frm_1","part_id":"p_1","name":"   ","fields":[],"min_filled_fields":0}"#
        )

        #expect(named.name == "Waiting contact")
        #expect(blank.name == nil)
    }

    @Test("a full show_form decodes its inline definition")
    func fullShowForm() throws {
        let form = try self.decode(ShowForm.self, """
            {
              "type": "show_form",
              "form_id": "frm_1",
              "part_id": "p_1",
              "name": "Callback",
              "confirmation_text": "Thanks, we will call you back.",
              "fields": [{ "key": "phone", "label": "Phone", "type": "tel" }],
              "min_filled_fields": 1
            }
            """)

        #expect(form.name == "Callback")
        #expect(form.confirmationText == "Thanks, we will call you back.")
        #expect(form.fields.map(\.key) == ["phone"])
        #expect(form.minFilledFields == 1)
    }

    @Test("a show_form without form_id fails to decode")
    func showFormWithoutFormIDThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(ShowForm.self, #"{"type":"show_form","part_id":"p_1"}"#)
        }
    }

    // MARK: - Fixtures

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try self.decoder.decode(type, from: Data(json.utf8))
    }
}
