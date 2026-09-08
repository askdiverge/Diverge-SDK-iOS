//
//  FormValidatorTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("FormValidator")
struct FormValidatorTests {

    private let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [
            .init(key: "name", label: "Name", type: .text, required: true),
            .init(key: "email", label: "Email", type: .email, required: true),
            .init(key: "message", label: "Message", type: .textarea, required: true)
        ]
    ))

    @Test("required empty fields produce per-field errors")
    func requiredEmpty() {
        let result = FormValidator.validate(form: self.contact, values: [:])
        #expect(result.fieldErrors.keys.sorted() == ["email", "message", "name"])
        #expect(result.isValid == false)
    }

    @Test("a filled contact form is valid")
    func filledContactValid() {
        let result = FormValidator.validate(form: self.contact, values: [
            "name": "Jane",
            "email": "jane@example.com",
            "message": "Help"
        ])
        #expect(result.isValid)
    }

    @Test("invalid email is rejected when non-empty")
    func invalidEmail() {
        let result = FormValidator.validate(form: self.contact, values: [
            "name": "Jane",
            "email": "not-an-email",
            "message": "Help"
        ])
        #expect(result.fieldErrors["email"] == L10n.formInvalidEmail.string)
    }

    @Test("visible_when hides a field until its dropdown matches")
    func visibleWhenHides() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "distributor", label: "D", type: .dropdown, required: true, options: ["a", "b"]),
                .init(
                    key: "claim",
                    label: "Claim",
                    type: .textarea,
                    required: true,
                    visibleWhen: [.init(field: "distributor", value: "a")]
                )
            ],
            minFilledFields: 0
        ))

        let hidden = FormValidator.validate(form: form, values: ["distributor": "b"])
        #expect(hidden.fieldErrors["claim"] == nil, "hidden required field is not validated")
        #expect(hidden.isValid)

        let shown = FormValidator.validate(form: form, values: ["distributor": "a"])
        #expect(shown.fieldErrors["claim"] == L10n.formRequired.string)
    }

    @Test("min_filled_fields rejects when too few visible fields are filled")
    func minFilled() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "a", label: "A", type: .text),
                .init(key: "b", label: "B", type: .text),
                .init(key: "c", label: "C", type: .text)
            ],
            minFilledFields: 2
        ))

        let short = FormValidator.validate(form: form, values: ["a": "1"])
        #expect(short.formError == L10n.formMinFilled(2).string)
        #expect(short.isValid == false)

        let enough = FormValidator.validate(form: form, values: ["a": "1", "b": "2"])
        #expect(enough.isValid)
    }

    @Test("a required file field needs a picked file")
    func requiredFile() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [.init(key: "photo", label: "Photo", type: .file, required: true)],
            minFilledFields: 0
        ))

        let missing = FormValidator.validate(form: form, values: [:], files: [])
        #expect(missing.fieldErrors["photo"] == L10n.formRequired.string)

        let present = FormValidator.validate(form: form, values: [:], files: ["photo"])
        #expect(present.isValid)
    }

    @Test("email pattern matches the contract")
    func emailPattern() {
        #expect(FormValidator.isValidEmail("a@b.c"))
        #expect(FormValidator.isValidEmail("jane@example.com"))
        #expect(!FormValidator.isValidEmail(""))
        #expect(!FormValidator.isValidEmail("no-at"))
        #expect(!FormValidator.isValidEmail("@nodomain"))
        #expect(!FormValidator.isValidEmail("a@b"))
    }

    @Test("an email over the contract's 254 characters is rejected")
    func emailTooLong() {
        let local = String(repeating: "a", count: 250)
        let result = FormValidator.validate(form: self.contact, values: [
            "name": "Jane",
            "email": "\(local)@x.io",
            "message": "Help"
        ])
        #expect(result.fieldErrors["email"] == L10n.formInvalidEmail.string)
    }

    // MARK: - visible_when: the server's ordered forward pass

    /// A → B (when A = x) → C (when B = y).
    private let cascade = ConversationForm.custom(ShowForm(
        partId: "p",
        formId: "f",
        name: "F",
        fields: [
            .init(key: "a", label: "A", type: .dropdown, options: ["x", "z"]),
            .init(key: "b", label: "B", type: .dropdown, options: ["y", "w"],
                  visibleWhen: [.init(field: "a", operator: .equals, value: "x")]),
            .init(key: "c", label: "C", type: .text,
                  visibleWhen: [.init(field: "b", operator: .equals, value: "y")])
        ],
        minFilledFields: 0
    ))

    @Test("hiding a parent cascades: a dependent with a stale matching answer is hidden too")
    func cascadeHidesDependents() {
        let shown = FormValidator.visibleFields(of: self.cascade, values: ["a": "x", "b": "y"])
        #expect(shown.map(\.key) == ["a", "b", "c"])

        // The visitor flips A back — B's stale "y" must not keep C visible.
        let flipped = FormValidator.visibleFields(of: self.cascade, values: ["a": "z", "b": "y"])
        #expect(flipped.map(\.key) == ["a"])
    }

    @Test("the compared answer is trimmed, matching the server")
    func conditionValueIsTrimmed() {
        let shown = FormValidator.visibleFields(of: self.cascade, values: ["a": "  x \n"])
        #expect(shown.map(\.key) == ["a", "b"])
    }

    @Test("a condition on a later (or unknown) field never matches — single forward pass")
    func forwardReferenceIsHidden() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [
                .init(key: "early", label: "E", type: .text,
                      visibleWhen: [.init(field: "late", operator: .equals, value: "go")]),
                .init(key: "late", label: "L", type: .dropdown, options: ["go"]),
                .init(key: "orphan", label: "O", type: .text,
                      visibleWhen: [.init(field: "missing", operator: .equals, value: "go")])
            ],
            minFilledFields: 0
        ))
        let shown = FormValidator.visibleFields(of: form, values: ["late": "go", "missing": "go"])
        #expect(shown.map(\.key) == ["late"])
    }

    @Test("a file field on a contact form has no wire slot — never required, never counted")
    func contactFileFieldIsNotRequired() {
        let form = ConversationForm.contact(ShowContactForm(
            partId: "p",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "photo", label: "Photo", type: .file, required: true)
            ]
        ))
        #expect(form.acceptsFileFields == false)
        let result = FormValidator.validate(form: form, values: ["name": "Jane"], files: [])
        #expect(result.isValid)
    }
}
