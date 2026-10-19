//
//  FormActionBuilderTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("FormActionBuilder")
struct FormActionBuilderTests {

    @Test("contact form builds a contact_form action with trimmed visible fields")
    func contactBuilds() {
        let form = ConversationForm.contact(ShowContactForm(
            partId: "part_contact_1",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(key: "orderNumber", label: "Order", type: .text)
            ]
        ))

        let request = FormActionBuilder.build(
            form: form,
            values: [
                "name": "  Jane  ",
                "email": "jane@example.com",
                "orderNumber": "ABC-123",
                "hiddenNoise": "ignored"
            ]
        )

        #expect(request == SubmitActionRequest(
            partId: "part_contact_1",
            action: .contactForm(fields: [
                "name": "Jane",
                "email": "jane@example.com",
                "orderNumber": "ABC-123"
            ])
        ))
    }

    @Test("support ticket builds name/email/message")
    func ticketBuilds() throws {
        let form = try #require(ConversationForm.supportTicket(ShowSupportTicket(
            partId: "part_ticket_1",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(key: "message", label: "Message", type: .textarea, required: true)
            ]
        )))

        let request = FormActionBuilder.build(
            form: form,
            values: ["name": "Jane", "email": "j@e.c", "message": "Broken"]
        )

        #expect(request == SubmitActionRequest(
            partId: "part_ticket_1",
            action: .supportTicket(
                name: "Jane",
                email: "j@e.c",
                message: "Broken",
                attachments: nil
            )
        ))
    }

    @Test("a ticket form keeps only the fields its action carries")
    func ticketDropsUncarriedFields() throws {
        let form = try #require(ConversationForm.supportTicket(ShowSupportTicket(
            partId: "part_ticket_1",
            fields: [
                .init(key: "name", label: "Name"),
                .init(key: "order_number", label: "Order"),
                .init(key: "email", label: "Email", type: .email),
                .init(key: "message", label: "Message", type: .textarea)
            ]
        )))

        #expect(form.fields.map(\.key) == ["name", "email", "message"])
    }

    @Test("a ticket marker missing one of name, email or message renders no form")
    func ticketWithoutWireFieldsIsSkipped() {
        let form = ConversationForm.supportTicket(ShowSupportTicket(
            partId: "part_ticket_1",
            fields: [
                .init(key: "full_name", label: "Name"),
                .init(key: "email", label: "Email", type: .email),
                .init(key: "description", label: "Description", type: .textarea)
            ]
        ))

        #expect(form == nil)
    }

    @Test("custom form excludes hidden fields and file fields")
    func customExcludesHidden() {
        let form = ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "salesLead",
            name: "Sales",
            fields: [
                .init(key: "distributor", label: "D", type: .dropdown, options: ["a", "b"]),
                .init(
                    key: "claim",
                    label: "Claim",
                    type: .textarea,
                    visibleWhen: [.init(field: "distributor", value: "a")]
                ),
                .init(key: "photo", label: "Photo", type: .file)
            ],
            minFilledFields: 0
        ))

        let request = FormActionBuilder.build(
            form: form,
            values: [
                "distributor": "b",
                "claim": "should be excluded",
                "photo": "should be excluded"
            ]
        )

        #expect(request == SubmitActionRequest(
            partId: "part_form_1",
            action: .formSubmission(
                formId: "salesLead",
                values: ["distributor": "b"],
                files: nil
            )
        ))
    }

    @Test("a cascade-hidden field is excluded even when its own condition still matches")
    func cascadeHiddenExcluded() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "a", label: "A", type: .dropdown, options: ["x", "z"]),
                .init(key: "b", label: "B", type: .dropdown, options: ["y"],
                      visibleWhen: [.init(field: "a", operator: .equals, value: "x")]),
                .init(key: "c", label: "C", type: .text,
                      visibleWhen: [.init(field: "b", operator: .equals, value: "y")])
            ],
            minFilledFields: 0
        ))
        let request = FormActionBuilder.build(form: form, values: ["a": "z", "b": "y", "c": "stale"])
        #expect(request?.action == .formSubmission(formId: "f", values: ["a": "z"], files: nil))
    }

    @Test("a contact form whose only answer is a file has nothing to send")
    func contactWithOnlyFileIsNil() {
        let form = ConversationForm.contact(ShowContactForm(
            partId: "p",
            fields: [.init(key: "photo", label: "Photo", type: .file)]
        ))
        #expect(FormActionBuilder.build(form: form, values: ["photo": "photo.jpg"]) == nil)
    }
}
