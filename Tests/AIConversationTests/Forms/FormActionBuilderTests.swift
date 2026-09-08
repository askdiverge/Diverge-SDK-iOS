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

    @Test("support ticket builds name/email/message plus optional attachments")
    func ticketBuilds() {
        let form = ConversationForm.supportTicket(ShowSupportTicket(
            partId: "part_ticket_1",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(key: "message", label: "Message", type: .textarea, required: true)
            ]
        ))
        let attachment = OutgoingAttachment(
            kind: .image,
            data: "QQ==",
            mime: "image/jpeg",
            filename: "photo.jpg"
        )

        let request = FormActionBuilder.build(
            form: form,
            values: ["name": "Jane", "email": "j@e.c", "message": "Broken"],
            ticketAttachments: [attachment]
        )

        #expect(request == SubmitActionRequest(
            partId: "part_ticket_1",
            action: .supportTicket(
                name: "Jane",
                email: "j@e.c",
                message: "Broken",
                attachments: [attachment]
            )
        ))
    }

    @Test("custom form excludes hidden fields and splits values from files")
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
        let file = OutgoingAttachment(
            kind: .image,
            data: "QQ==",
            mime: "image/jpeg",
            filename: "photo.jpg"
        )

        let request = FormActionBuilder.build(
            form: form,
            values: [
                "distributor": "b",
                "claim": "should be excluded"
            ],
            files: ["photo": file]
        )

        #expect(request == SubmitActionRequest(
            partId: "part_form_1",
            action: .formSubmission(
                formId: "salesLead",
                values: ["distributor": "b"],
                files: ["photo": file]
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

    @Test("ticket attachments are ignored for a custom form — they have no slot on form_submission")
    func ticketAttachmentsIgnoredForCustom() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [.init(key: "note", label: "Note", type: .text)],
            minFilledFields: 0
        ))
        let stray = OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "x.jpg")
        let request = FormActionBuilder.build(form: form, values: ["note": "hi"], ticketAttachments: [stray])
        #expect(request?.action == .formSubmission(formId: "f", values: ["note": "hi"], files: nil))
    }

    @Test("a contact form whose only answer is a file has nothing to send")
    func contactWithOnlyFileIsNil() {
        let form = ConversationForm.contact(ShowContactForm(
            partId: "p",
            fields: [.init(key: "photo", label: "Photo", type: .file)]
        ))
        let file = OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "photo.jpg")
        #expect(FormActionBuilder.build(form: form, values: [:], files: ["photo": file]) == nil)
    }
}
