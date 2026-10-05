//
//  FormValidationErrorTests.swift
//  AIConversationTests
//

import Foundation
import Testing
import AIConversationCore
@testable import AIConversation
@testable import AIConversationEngine

@Suite("Form validation — server params")
@MainActor
struct FormValidationErrorTests {

    private let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [
            .init(key: "name", label: "Name", type: .text, required: true),
            .init(key: "email", label: "Email", type: .email, required: true)
        ]
    ))

    @Test("FormSubmissionModel maps params to field errors")
    func submissionModelApply() {
        var model = FormSubmissionModel(form: self.contact)
        _ = model.beginSubmitting()
        model.applyServerErrors(
            params: [ValidationError(field: "email", message: "Bad email")],
            formMessage: "Fix the form"
        )
        #expect(model.phase == .editing)
        #expect(model.fieldErrors["email"] == "Bad email")
        #expect(model.formError == "Fix the form")
        #expect(model.isSubmitting == false)
    }

    @Test("duplicate params field keys last-wins and do not crash")
    func duplicateParamsLastWins() {
        var model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(
            params: [
                ValidationError(field: "email", message: "first"),
                ValidationError(field: "email", message: "last")
            ],
            formMessage: nil
        )
        #expect(model.fieldErrors["email"] == "last")
        #expect(model.formError == nil)
    }

    @Test("unmatched params join formError; envelope banner is kept")
    func unmatchedParamsJoinFormError() {
        var model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(
            params: [
                ValidationError(field: "email", message: "Bad email"),
                ValidationError(field: "unknown", message: "Not a field")
            ],
            formMessage: "Fix the form"
        )
        #expect(model.fieldErrors["email"] == "Bad email")
        #expect(model.fieldErrors["unknown"] == nil)
        #expect(model.formError == "Fix the form\nNot a field")
    }

    @Test("an error for a hidden field joins the banner")
    func hiddenFieldErrorJoinsBanner() {
        var model = FormSubmissionModel(form: ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "topic", label: "Topic", type: .dropdown, options: ["billing", "other"]),
                .init(
                    key: "invoice",
                    label: "Invoice",
                    visibleWhen: [.init(field: "topic", value: "billing")]
                )
            ]
        )))

        model.applyServerErrors(
            params: [ValidationError(field: "invoice", message: "Invoice is required")],
            formMessage: nil
        )

        #expect(model.fieldErrors["invoice"] == nil)
        #expect(model.formError == "Invoice is required")
    }

    @Test("a required file field does not block the submit while photo attach is unavailable")
    func fileFieldIsNeverRequired() {
        let form = ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "receipt", label: "Receipt", type: .file, required: true),
                .init(key: "note", label: "Note")
            ]
        ))

        #expect(FormValidator.validate(form: form, values: ["note": "hi"]).isValid)
    }

    @Test("an email answer must match the contract pattern")
    func emailPattern() {
        let invalid = FormValidator.validate(form: self.contact, values: ["name": "Jane", "email": "jane@example"])
        let valid = FormValidator.validate(form: self.contact, values: ["name": "Jane", "email": " jane@example.com "])

        #expect(invalid.fieldErrors["email"] == L10n.formInvalidEmail.string)
        #expect(valid.isValid)
    }

    @Test("min_filled_fields counts visible, non-empty answers")
    func minFilledFields() {
        let form = ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "a", label: "A"),
                .init(key: "b", label: "B"),
                .init(key: "receipt", label: "Receipt", type: .file)
            ],
            minFilledFields: 2
        ))

        let one = FormValidator.validate(form: form, values: ["a": "x", "b": "  ", "receipt": "x"])
        let two = FormValidator.validate(form: form, values: ["a": "x", "b": "y"])

        #expect(one.formError == L10n.formMinFilled(2).string)
        #expect(two.isValid)
    }
}
