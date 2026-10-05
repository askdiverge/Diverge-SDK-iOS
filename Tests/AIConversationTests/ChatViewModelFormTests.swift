//
//  ChatViewModelFormTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — form submission")
@MainActor
struct ChatViewModelFormTests {

    private let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [
            .init(key: "name", label: "Name", type: .text, required: true),
            .init(key: "email", label: "Email", type: .email, required: true),
            .init(key: "message", label: "Message", type: .textarea, required: true)
        ]
    ))

    @Test("a successful submit collapses the form to the server confirmation")
    func submitSuccess() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!")
            }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(self.draft(in: viewModel)?.phase == .submitted(confirmation: "Got it!"))
    }

    @Test("a transport failure leaves the form editable with a card-level error")
    func submitFailure() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                throw ChatServiceError.transport(.http(.unhandled(status: 500, body: Data())))
            }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(self.draft(in: viewModel)?.phase == .failed(L10n.formSubmitFailed.string))
    }

    @Test("session expiry on submit rethrows SessionEnded")
    func submitSessionExpired() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                throw ChatServiceError.sessionExpired
            }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)

        do {
            try await viewModel.submitForm(partId: self.contact.partId)
            Issue.record("expected SessionEnded")
        } catch {
            // typed throws(SessionEnded)
        }
    }

    @Test("only the newest bot turn is editable")
    func isFormEditableMatchesLastBot() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        let olderID = UUID()
        let newerID = UUID()
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [
                Identified(id: olderID, model: [.form(self.contact)]),
                Identified(id: newerID, model: [.text(AttributedString("ok"))])
            ],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))

        try await eventually { viewModel.snapshot?.lastBotTurnID == newerID }

        #expect(viewModel.isFormEditable(inBotTurn: newerID))
        #expect(!viewModel.isFormEditable(inBotTurn: olderID))
    }

    @Test("client validation blocks the submit without calling the service")
    func validationBlocksSubmit() async throws {
        let called = Box(false)
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                called.value = true
                return SubmitActionResponse(submissionId: "x")
            }
        )
        try await self.show(self.contact, on: provider, in: viewModel)

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(called.value == false)
        #expect(self.draft(in: viewModel)?.fieldErrors.isEmpty == false)
    }

    @Test("submitForm for an unknown partId is a no-op")
    func unknownPartIdNoop() async throws {
        let called = Box(false)
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            submitAction: { _ in
                called.value = true
                return SubmitActionResponse(submissionId: "x")
            }
        )
        try await viewModel.submitForm(partId: "part_nobody")
        #expect(called.value == false)
    }

    @Test("confirmation precedence: server text, then the marker's inline copy, then the SDK default")
    func confirmationPrecedence() {
        let inline = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            confirmationText: "Inline thanks",
            fields: [.init(key: "a", label: "A", type: .text)],
            minFilledFields: 0
        ))
        #expect(FormSubmissionModel.confirmation(server: "Server thanks", form: inline) == "Server thanks")
        #expect(FormSubmissionModel.confirmation(server: "  \n", form: inline) == "Inline thanks")
        #expect(FormSubmissionModel.confirmation(server: nil, form: inline) == "Inline thanks")
        #expect(FormSubmissionModel.confirmation(server: nil, form: self.contact) == L10n.formSubmittedDefault.string)
    }

    @Test("a submitted form stays submitted when a later snapshot brings it again")
    func submittedDraftSurvivesSnapshots() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!") }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)
        try await viewModel.submitForm(partId: self.contact.partId)

        let laterTurn = UUID()
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [Identified(model: [.form(self.contact)]), Identified(id: laterTurn, model: [])],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))
        try await eventually { viewModel.snapshot?.lastBotTurnID == laterTurn }

        #expect(self.draft(in: viewModel)?.phase == .submitted(confirmation: "Got it!"))
    }

    @Test("a second submit while the first is in flight does not call the service again")
    func submitIsSingleFlight() async throws {
        let calls = Box(0)
        let gate = AsyncGate()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                calls.value += 1
                await gate.wait()
                return SubmitActionResponse(submissionId: "sub_1")
            }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)

        let first = Task { try await viewModel.submitForm(partId: self.contact.partId) }
        try await eventually { self.draft(in: viewModel)?.isSubmitting == true }
        try await viewModel.submitForm(partId: self.contact.partId)
        await gate.open()
        try await first.value

        #expect(calls.value == 1)
        #expect(self.draft(in: viewModel)?.isSubmitted == true)
    }

    @Test("reset drops cached form drafts")
    func resetClearsFormModels() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        try await self.show(self.contact, on: provider, in: viewModel)
        viewModel.setFormValue("Jane", for: "name", inForm: self.contact.partId)

        await viewModel.reset()

        #expect(viewModel.formModels.isEmpty)
    }

    @Test("failed reset keeps form drafts")
    func failedResetKeepsDrafts() async throws {
        let provider = StubChatProviding()
        provider.resetError = StubResetError.failed
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!") }
        )
        try await self.show(self.contact, on: provider, in: viewModel)
        self.fillContact(in: viewModel)
        try await viewModel.submitForm(partId: self.contact.partId)

        await viewModel.reset()

        #expect(self.draft(in: viewModel)?.phase == .submitted(confirmation: "Got it!"))
        #expect(viewModel.notice == nil)
    }

    // MARK: - Thin custom forms

    @Test("a thin show_form fills in its fields and name from the fetched definition")
    func thinFormHydrates() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            fetchForm: { _ in try Self.definition() }
        )

        try await self.show(self.thinForm, on: provider, in: viewModel)
        try await eventually { viewModel.formModels[self.thinForm.partId]?.hasFields == true }

        let draft = try #require(viewModel.formModels[self.thinForm.partId])
        #expect(draft.form.fields.map(\.key) == ["phone"])
        #expect(draft.form.displayName == "Callback")
        #expect(!draft.isHydrating)
    }

    @Test("a failed definition fetch marks the card failed, and a retry fills it in")
    func thinFormRetriesAfterFailure() async throws {
        let attempts = Box(0)
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            fetchForm: { _ in
                attempts.value += 1
                if attempts.value == 1 { throw ChatServiceError.transport(.http(.unhandled(status: 404, body: Data()))) }
                return try Self.definition()
            }
        )

        try await self.show(self.thinForm, on: provider, in: viewModel)
        try await eventually { viewModel.formModels[self.thinForm.partId]?.hydrationFailed == true }
        viewModel.reloadFormDefinition(partId: self.thinForm.partId)
        try await eventually { viewModel.formModels[self.thinForm.partId]?.hasFields == true }

        #expect(attempts.value == 2)
        #expect(viewModel.formModels[self.thinForm.partId]?.hydrationFailed == false)
    }

    @Test("an unnamed thin form is titled with SDK copy, not its form_id")
    func unnamedThinFormUsesSDKTitle() {
        #expect(ConversationFormView.accessibilityLabel(for: self.thinForm) == L10n.formContactTitle.string)
    }

    // MARK: - Fixtures

    private let thinForm = ConversationForm.custom(ShowForm(
        partId: "part_form_1",
        formId: "callbackForm",
        name: nil,
        fields: [],
        minFilledFields: 0
    ))

    /// The `GET /forms/callbackForm` body the thin-form tests fetch.
    nonisolated private static func definition() throws -> ChatFormDefinition {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatFormDefinition.self, from: Data(#"""
            {"form_id":"callbackForm","name":"Callback","fields":[{"key":"phone","label":"Phone","type":"tel"}],"min_filled_fields":1}
            """#.utf8))
    }

    /// Publishes a snapshot whose bot turn holds `form`, and waits for the view model's draft.
    private func show(
        _ form: ConversationForm,
        on provider: StubChatProviding,
        in viewModel: ChatView.ViewModel
    ) async throws {
        provider.publish(ConversationSnapshot(
            user: [],
            incoming: [Identified(model: [.form(form)])],
            isUserInitiatedConversation: false,
            streamingTurnID: nil
        ))
        try await eventually { viewModel.formModels[form.partId] != nil }
    }

    private func fillContact(in viewModel: ChatView.ViewModel) {
        viewModel.setFormValue("Jane", for: "name", inForm: self.contact.partId)
        viewModel.setFormValue("jane@example.com", for: "email", inForm: self.contact.partId)
        viewModel.setFormValue("Help", for: "message", inForm: self.contact.partId)
    }

    private func draft(in viewModel: ChatView.ViewModel) -> FormSubmissionModel? {
        viewModel.formModels[self.contact.partId]
    }
}

private enum StubResetError: Error {
    case failed
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
