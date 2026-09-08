//
//  FormSubmissionModelTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("FormSubmissionModel")
@MainActor
struct FormSubmissionModelTests {

    private let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [
            .init(key: "name", label: "Name", type: .text, required: true),
            .init(key: "email", label: "Email", type: .email, required: true)
        ]
    ))

    @Test("editing after a failure returns the form to .editing")
    func editAfterFailure() {
        let model = FormSubmissionModel(form: self.contact)
        model.markFailed("nope")
        #expect(model.phase == .failed("nope"))

        model.setValue("Jane", for: "name")
        #expect(model.phase == .editing)

        model.markFailed()
        model.setFile(nil, for: "photo")
        #expect(model.phase == .editing)

        model.markFailed()
        model.setTicketAttachment(nil)
        #expect(model.phase == .editing)
    }

    @Test("beginSubmitting is single-flight and refuses once submitted")
    func beginSubmittingGuards() {
        let model = FormSubmissionModel(form: self.contact)
        #expect(model.beginSubmitting())
        #expect(model.isSubmitting)
        #expect(model.beginSubmitting() == false)

        model.markSubmitted(confirmation: "Thanks")
        #expect(model.beginSubmitting() == false)
        #expect(model.isSubmitted)
    }

    @Test("beginSubmitting after a failure is allowed and clears the form-level error")
    func beginSubmittingAfterFailure() {
        let model = FormSubmissionModel(form: self.contact)
        model.validate()
        #expect(model.fieldErrors.isEmpty == false)
        model.markFailed()
        #expect(model.beginSubmitting())
        #expect(model.formError == nil)
    }

    @Test("markSubmitted clears field and form errors")
    func markSubmittedClearsErrors() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "F",
            fields: [.init(key: "a", label: "A", type: .text), .init(key: "b", label: "B", type: .text)],
            minFilledFields: 2
        ))
        let model = FormSubmissionModel(form: form)
        model.validate()
        #expect(model.formError != nil)

        model.markSubmitted(confirmation: "Done")
        #expect(model.fieldErrors.isEmpty)
        #expect(model.formError == nil)
        #expect(model.phase == .submitted(confirmation: "Done"))
    }

    @Test("a recorded confirmation seeds the model collapsed")
    func seededFromStore() {
        let model = FormSubmissionModel(form: self.contact, submittedConfirmation: "Already in")
        #expect(model.phase == .submitted(confirmation: "Already in"))
        #expect(model.beginSubmitting() == false)
    }

    @Test("a marker with no decodable fields has nothing to submit")
    func hasFields() {
        let empty = ConversationForm.contact(ShowContactForm(partId: "p", fields: []))
        #expect(FormSubmissionModel(form: empty).hasFields == false)
        #expect(FormSubmissionModel(form: self.contact).hasFields)
    }

    @Test("buildRequest passes picked files and ticket attachments as wire attachments")
    func buildRequestMapsAttachments() {
        let ticket = ConversationForm.supportTicket(ShowSupportTicket(
            partId: "part_ticket_1",
            fields: [
                .init(key: "name", label: "Name", type: .text, required: true),
                .init(key: "email", label: "Email", type: .email, required: true),
                .init(key: "message", label: "Message", type: .textarea, required: true)
            ],
            attachmentsAccepted: true
        ))
        let model = FormSubmissionModel(form: ticket)
        model.setValue("Jane", for: "name")
        model.setValue("jane@example.com", for: "email")
        model.setValue("Broken", for: "message")
        let attachment = OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/jpeg", filename: "a.jpg")
        model.setTicketAttachment(PendingAttachment(
            thumbnail: Image(systemName: "photo"),
            attachment: attachment,
            displayName: "Image"
        ))

        #expect(model.buildRequest()?.action == .supportTicket(
            name: "Jane",
            email: "jane@example.com",
            message: "Broken",
            attachments: [attachment]
        ))
    }
}

@Suite("SubmittedFormStore")
struct SubmittedFormStoreTests {

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("submitted-forms-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("submitted.json")
    }

    @Test("a recorded part id survives a fresh store over the same file")
    func persistsAcrossInstances() {
        let url = self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        SubmittedFormStore(fileURL: url).record(partId: "part_1", confirmation: "Thanks")

        let reloaded = SubmittedFormStore(fileURL: url)
        #expect(reloaded.confirmation(for: "part_1") == "Thanks")
        #expect(reloaded.confirmation(for: "part_2") == nil)
    }

    @Test("removeAll forgets everything on disk too")
    func removeAll() {
        let url = self.temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SubmittedFormStore(fileURL: url)
        store.record(partId: "part_1", confirmation: "Thanks")
        store.removeAll()

        #expect(store.confirmation(for: "part_1") == nil)
        #expect(SubmittedFormStore(fileURL: url).confirmation(for: "part_1") == nil)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("the store is bounded — oldest entries fall off past maxEntries")
    func bounded() {
        let store = SubmittedFormStore(fileURL: nil)
        for index in 0...SubmittedFormStore.maxEntries {
            store.record(partId: "part_\(index)", confirmation: "c")
        }
        #expect(store.confirmation(for: "part_0") == nil)
        #expect(store.confirmation(for: "part_\(SubmittedFormStore.maxEntries)") == "c")
    }

    @Test("re-recording a part id replaces its confirmation")
    func rerecordReplaces() {
        let store = SubmittedFormStore(fileURL: nil)
        store.record(partId: "part_1", confirmation: "first")
        store.record(partId: "part_1", confirmation: "second")
        #expect(store.confirmation(for: "part_1") == "second")
    }
}
