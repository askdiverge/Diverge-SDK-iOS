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

    @Test("a body-path param puts the SDK's copy under the field it names, with no banner")
    func submissionModelApply() {
        var model = FormSubmissionModel(form: self.contact)
        _ = model.beginSubmitting()
        model.applyServerErrors(params: [ValidationError(field: "action.fields.email", message: "Bad email")])
        #expect(model.phase == .editing)
        #expect(model.fieldErrors["email"] == L10n.formFieldRejected.string)
        #expect(model.formError == nil)
        #expect(model.isSubmitting == false)
    }

    @Test("every action body path names its last segment")
    func fieldKeyFromPath() {
        #expect(FormServerErrors.fieldKey("action.fields.email") == "email")
        #expect(FormServerErrors.fieldKey("action.values.orderNumber") == "orderNumber")
        #expect(FormServerErrors.fieldKey("action.files.photo") == "photo")
        #expect(FormServerErrors.fieldKey("action.email") == "email")
        #expect(FormServerErrors.fieldKey("values.email") == "email")
        #expect(FormServerErrors.fieldKey("email") == "email")
    }

    @Test("duplicate params for one field leave one error and do not crash")
    func duplicateParamsLastWins() {
        var model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(
            params: [
                ValidationError(field: "action.fields.email", message: "first"),
                ValidationError(field: "action.fields.email", message: "last")
            ]
        )
        #expect(model.fieldErrors == ["email": L10n.formFieldRejected.string])
        #expect(model.formError == nil)
    }

    @Test("an unmatched param, or a rejection without params, shows the localized banner")
    func unmatchedParamsShowLocalizedBanner() {
        var model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(params: [
            ValidationError(field: "action.fields.email", message: "Bad email"),
            ValidationError(field: "part_id", message: "part_id must reference the latest assistant action part")
        ])
        #expect(model.fieldErrors["email"] == L10n.formFieldRejected.string)
        #expect(model.formError == L10n.formSubmitFailed.string)

        model.applyServerErrors(params: [])
        #expect(model.fieldErrors.isEmpty)
        #expect(model.formError == L10n.formSubmitFailed.string)
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

        model.applyServerErrors(params: [ValidationError(field: "action.values.invoice", message: "Invoice is required")])

        #expect(model.fieldErrors["invoice"] == nil)
        #expect(model.formError == L10n.formSubmitFailed.string)
    }

    @Test("a required file field blocks submit until a photo is attached")
    func requiredFileNeedsPick() {
        let form = Self.receiptForm(type: .file)

        let missing = FormValidator.validate(form: form, values: ["note": "hi"], files: [], offersFileFields: true)
        let present = FormValidator.validate(form: form, values: ["note": "hi"], files: ["receipt"], offersFileFields: true)

        #expect(missing.fieldErrors["receipt"] == L10n.formRequired.string)
        #expect(present.isValid)
    }

    @Test(
        "a required field this app can't fill makes the form unavailable",
        arguments: zip([FormField.FieldType.file, .unknown], [false, true])
    )
    func unfillableRequiredFieldBlocks(type: FormField.FieldType, offersFileFields: Bool) {
        let form = Self.receiptForm(type: type)
        var model = FormSubmissionModel(form: form)
        model.setValue("hi", for: "note")

        #expect(FormValidator.blockingField(of: form, values: model.values, offersFileFields: offersFileFields)?.key == "receipt")
        #expect(
            FormValidator.validate(form: form, values: model.values, files: [], offersFileFields: offersFileFields).formError
                == L10n.formUnavailable.string
        )
        #expect(model.isCompletable(offersFileFields: offersFileFields) == false)
    }

    @Test("an optional field this app can't fill is skipped")
    func unfillableOptionalFieldIsSkipped() {
        let form = ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "when", label: "When", type: .unknown),
                .init(key: "note", label: "Note")
            ]
        ))

        #expect(FormValidator.blockingField(of: form, values: [:], offersFileFields: true) == nil)
        #expect(FormValidator.validate(form: form, values: ["note": "hi"], files: [], offersFileFields: true).isValid)
    }

    @Test("an all-optional contact or custom form needs one answer before it sends")
    func emptyOptionalFormNeedsOneAnswer() {
        let form = ConversationForm.contact(ShowContactForm(
            partId: "part_contact_1",
            fields: [.init(key: "name", label: "Name"), .init(key: "phone", label: "Phone", type: .tel)]
        ))

        #expect(FormValidator.validate(form: form, values: [:], files: [], offersFileFields: true).formError == L10n.formMinFilled(1).string)
        #expect(FormValidator.validate(form: form, values: ["phone": "123"], files: [], offersFileFields: true).isValid)
    }

    @Test("an email answer must match the contract pattern")
    func emailPattern() {
        let invalid = FormValidator.validate(form: self.contact, values: ["name": "Jane", "email": "jane@example"], files: [], offersFileFields: true)
        let valid = FormValidator.validate(form: self.contact, values: ["name": "Jane", "email": " jane@example.com "], files: [], offersFileFields: true)

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

        let one = FormValidator.validate(form: form, values: ["a": "x", "b": "  "], files: [], offersFileFields: true)
        let withFile = FormValidator.validate(
            form: form,
            values: ["a": "x", "b": "  "],
            files: ["receipt"],
            offersFileFields: true
        )
        let two = FormValidator.validate(form: form, values: ["a": "x", "b": "y"], files: [], offersFileFields: true)

        #expect(one.formError == L10n.formMinFilled(2).string)
        #expect(withFile.isValid)
        #expect(two.isValid)
    }

    /// A custom form with a required `receipt` field of `type` and an optional note.
    private static func receiptForm(type: FormField.FieldType) -> ConversationForm {
        ConversationForm.custom(ShowForm(
            partId: "part_form_1",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "receipt", label: "Receipt", type: type, required: true),
                .init(key: "note", label: "Note")
            ]
        ))
    }
}
