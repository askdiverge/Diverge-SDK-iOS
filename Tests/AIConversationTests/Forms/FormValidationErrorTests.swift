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
        let model = FormSubmissionModel(form: self.contact)
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

    @Test("WaitingFormModel maps params to field errors")
    func waitingModelApply() {
        let definition = ChatFormDefinition(
            formId: "waiting",
            name: "Waiting",
            trigger: .livechatWaiting,
            fields: [.init(key: "email", label: "Email", type: .email, required: false)],
            minFilledFields: 1
        )
        let model = WaitingFormModel(definition: definition)
        _ = model.beginSaving()
        model.applyServerErrors(
            params: [ValidationError(field: "email", message: "Required")],
            formMessage: nil
        )
        #expect(model.phase == .editing)
        #expect(model.fieldErrors["email"] == "Required")
        #expect(model.formError == nil)
    }

    @Test("submitForm surfaces 422 field errors on the card")
    func submitFormValidation() async throws {
        let validation = ChatServiceError.validation(
            message: "Check your answers",
            params: [ValidationError(field: "email", message: "Invalid")]
        )
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            submitAction: { _ in throw validation }
        )
        viewModel.formModel(for: self.contact).setValue("Jane", for: "name")
        viewModel.formModel(for: self.contact).setValue("jane@example.com", for: "email")
        viewModel.formModel(for: self.contact).setValue("Help", for: "message")

        try await viewModel.submitForm(partId: self.contact.partId)

        let model = viewModel.formModel(for: self.contact)
        #expect(model.fieldErrors["email"] == "Invalid")
        #expect(model.formError == "Check your answers")
        #expect(model.phase == .editing)
    }

    @Test("duplicate params field keys last-wins and do not crash")
    func duplicateParamsLastWins() {
        let model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(
            params: [
                ValidationError(field: "email", message: "first"),
                ValidationError(field: "email", message: "last"),
            ],
            formMessage: nil
        )
        #expect(model.fieldErrors["email"] == "last")
        #expect(model.formError == nil)

        let waiting = WaitingFormModel(definition: ChatFormDefinition(
            formId: "waiting",
            trigger: .livechatWaiting,
            fields: [.init(key: "email", label: "Email", type: .email)],
            minFilledFields: 1
        ))
        waiting.applyServerErrors(
            params: [
                ValidationError(field: "email", message: "first"),
                ValidationError(field: "email", message: "last"),
            ],
            formMessage: nil
        )
        #expect(waiting.fieldErrors["email"] == "last")
        #expect(waiting.formError == nil)
    }

    @Test("unmatched params join formError; envelope banner is kept")
    func unmatchedParamsJoinFormError() {
        let model = FormSubmissionModel(form: self.contact)
        model.applyServerErrors(
            params: [
                ValidationError(field: "email", message: "Bad email"),
                ValidationError(field: "unknown", message: "Not a field"),
            ],
            formMessage: "Fix the form"
        )
        #expect(model.fieldErrors["email"] == "Bad email")
        #expect(model.fieldErrors["unknown"] == nil)
        #expect(model.formError == "Fix the form\nNot a field")

        let waiting = WaitingFormModel(definition: ChatFormDefinition(
            formId: "waiting",
            trigger: .livechatWaiting,
            fields: [.init(key: "email", label: "Email", type: .email)],
            minFilledFields: 1
        ))
        waiting.applyServerErrors(
            params: [ValidationError(field: "honeypot", message: "Leave blank")],
            formMessage: nil
        )
        #expect(waiting.fieldErrors.isEmpty)
        #expect(waiting.formError == "Leave blank")
    }
}
