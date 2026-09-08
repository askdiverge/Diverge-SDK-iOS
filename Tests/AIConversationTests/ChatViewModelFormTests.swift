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
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(model.isSubmitted)
        if case .submitted(let text) = model.phase {
            #expect(text == "Got it!")
        } else {
            Issue.record("expected submitted")
        }
    }

    @Test("a transport failure leaves the form editable with a card-level error")
    func submitFailure() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                throw ChatServiceError.transport(.http(.unhandled(status: 500)))
            }
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(model.isSubmitted == false)
        if case .failed(let message) = model.phase {
            #expect(message == L10n.formSubmitFailed.string)
        } else {
            Issue.record("expected failed")
        }
    }

    @Test("session expiry on submit rethrows SessionEnded")
    func submitSessionExpired() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in
                throw ChatServiceError.sessionExpired
            }
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")

        do {
            try await viewModel.submitForm(partId: self.contact.partId)
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            // expected
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
    }

    @Test("only the newest bot turn is editable")
    func isFormEditableMatchesLastBot() async throws {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        let olderID = UUID()
        let newerID = UUID()
        provider.publish(ConversationSnapshot(
            turns: [
                Identified(id: olderID, model: .bot([.form(self.contact)])),
                Identified(id: newerID, model: .bot([.text(AttributedString("ok"))]))
            ],
            streamingTurnID: nil,
            canLoadOlder: false
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
        _ = viewModel.formModel(for: self.contact)

        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(called.value == false)
        #expect(viewModel.formModel(for: self.contact).fieldErrors.isEmpty == false)
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
        #expect(ChatView.ViewModel.confirmationText(server: "Server thanks", form: inline) == "Server thanks")
        #expect(ChatView.ViewModel.confirmationText(server: "  \n", form: inline) == "Inline thanks")
        #expect(ChatView.ViewModel.confirmationText(server: nil, form: inline) == "Inline thanks")
        #expect(ChatView.ViewModel.confirmationText(server: nil, form: self.contact) == L10n.formSubmittedDefault.string)
    }

    @Test("a successful submit is recorded so the same part id starts collapsed next time")
    func submitRecordsToStore() async throws {
        let store = SubmittedFormStore(fileURL: nil)
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            submitAction: { _ in SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!") },
            submittedForms: store
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")
        try await viewModel.submitForm(partId: self.contact.partId)

        #expect(store.confirmation(for: self.contact.partId) == "Got it!")

        // A second view model over the same store (a relaunch) sees the form as submitted.
        let relaunched = ChatView.ViewModel.forTesting(provider: StubChatProviding(), submittedForms: store)
        #expect(relaunched.formModel(for: self.contact).phase == .submitted(confirmation: "Got it!"))
    }

    @Test("a second submit while the first is in flight does not call the service again")
    func submitIsSingleFlight() async throws {
        let calls = Box(0)
        let gate = AsyncGate()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            submitAction: { _ in
                calls.value += 1
                await gate.wait()
                return SubmitActionResponse(submissionId: "sub_1")
            }
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")

        let first = Task { try await viewModel.submitForm(partId: self.contact.partId) }
        try await eventually { model.isSubmitting }
        try await viewModel.submitForm(partId: self.contact.partId)
        await gate.open()
        try await first.value

        #expect(calls.value == 1)
        #expect(model.isSubmitted)
    }

    @Test("reset drops cached form drafts")
    func resetClearsFormModels() async {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")

        await viewModel.reset()

        let fresh = viewModel.formModel(for: self.contact)
        #expect(fresh !== model)
        #expect(fresh.values.isEmpty)
    }

    @Test("reset forgets persisted submitted part ids")
    func resetPrunesSubmittedForms() async throws {
        let store = SubmittedFormStore(fileURL: nil)
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            submitAction: { _ in SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!") },
            submittedForms: store
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")
        try await viewModel.submitForm(partId: self.contact.partId)
        #expect(store.confirmation(for: self.contact.partId) == "Got it!")

        await viewModel.reset()

        #expect(store.confirmation(for: self.contact.partId) == nil)
        let relaunched = ChatView.ViewModel.forTesting(provider: StubChatProviding(), submittedForms: store)
        #expect(relaunched.formModel(for: self.contact).isSubmitted == false)
    }

    @Test("failed reset keeps persisted submitted part ids")
    func failedResetKeepsSubmittedForms() async throws {
        let store = SubmittedFormStore(fileURL: nil)
        let provider = StubChatProviding()
        provider.resetError = StubResetError.failed
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            submitAction: { _ in SubmitActionResponse(submissionId: "sub_1", confirmationText: "Got it!") },
            submittedForms: store
        )
        let model = viewModel.formModel(for: self.contact)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Help", for: "message")
        try await viewModel.submitForm(partId: self.contact.partId)
        #expect(store.confirmation(for: self.contact.partId) == "Got it!")

        await viewModel.reset()

        #expect(store.confirmation(for: self.contact.partId) == "Got it!")
        #expect(viewModel.formModel(for: self.contact) === model)
        #expect(viewModel.notice?.message == L10n.noticeSendFailed.string)
    }
}

private enum StubResetError: Error {
    case failed
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
