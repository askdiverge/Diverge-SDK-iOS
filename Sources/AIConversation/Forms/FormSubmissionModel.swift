//
//  FormSubmissionModel.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine
import AIConversationCore

/// Per-form draft and submission state. Cached on the view model by `partId` so list
/// recycling does not wipe the visitor's answers.
@MainActor
@Observable
final class FormSubmissionModel {

    enum Phase: Equatable {
        case editing
        case submitting
        case submitted(confirmation: String)
        case failed(String)
    }

    let form: ConversationForm
    var values: [String: String] = [:]
    /// File-field picks keyed by `FormField.key` — the same chip model the composer uses.
    var files: [String: PendingAttachment] = [:]
    /// Extra attachments on a support-ticket form (when `attachmentsAccepted`).
    var ticketAttachments: [PendingAttachment] = []
    private(set) var fieldErrors: [String: String] = [:]
    private(set) var formError: String?
    private(set) var phase: Phase = .editing

    var isSubmitted: Bool {
        if case .submitted = self.phase { return true }
        return false
    }

    var isSubmitting: Bool {
        if case .submitting = self.phase { return true }
        return false
    }

    /// A marker whose `fields` all failed to decode has nothing to send — Submit stays disabled
    /// rather than failing on tap.
    var hasFields: Bool { !self.form.fields.isEmpty }

    /// - Parameter submittedConfirmation: A confirmation recorded by ``SubmittedFormStore`` on
    ///   an earlier launch; when present the model starts collapsed.
    init(form: ConversationForm, submittedConfirmation: String? = nil) {
        self.form = form
        if let submittedConfirmation {
            self.phase = .submitted(confirmation: submittedConfirmation)
        }
    }

    /// Sets a text / dropdown answer and clears that field's error.
    func setValue(_ value: String, for key: String) {
        self.values[key] = value
        self.fieldErrors[key] = nil
        if case .failed = self.phase { self.phase = .editing }
    }

    /// Attaches a picked photo to a file field (replacing any previous pick).
    func setFile(_ file: PendingAttachment?, for key: String) {
        if let file {
            self.files[key] = file
        } else {
            self.files.removeValue(forKey: key)
        }
        self.fieldErrors[key] = nil
        if case .failed = self.phase { self.phase = .editing }
    }

    /// Sets the ticket-level attachment (capped at one for v1 — mirrors the composer).
    func setTicketAttachment(_ file: PendingAttachment?) {
        self.ticketAttachments = file.map { [$0] } ?? []
        if case .failed = self.phase { self.phase = .editing }
    }

    /// Runs client-side validation. Returns `true` when the draft is ready to submit.
    @discardableResult
    func validate() -> Bool {
        let result = FormValidator.validate(
            form: self.form,
            values: self.values,
            files: Set(self.files.keys)
        )
        self.fieldErrors = result.fieldErrors
        self.formError = result.formError
        return result.isValid
    }

    /// Builds the wire request from the current draft, or `nil` if the builder cannot.
    func buildRequest() -> SubmitActionRequest? {
        FormActionBuilder.build(
            form: self.form,
            values: self.values,
            files: self.files.mapValues(\.attachment),
            ticketAttachments: self.ticketAttachments.map(\.attachment)
        )
    }

    /// Enters `.submitting`. Returns `false` (and changes nothing) when a submit is already in
    /// flight or the form is already submitted — the model guards re-entry itself rather than
    /// trusting the button's disabled state.
    func beginSubmitting() -> Bool {
        switch self.phase {
        case .submitting, .submitted:
            return false
        case .editing, .failed:
            self.phase = .submitting
            self.formError = nil
            return true
        }
    }

    func markSubmitted(confirmation: String) {
        self.phase = .submitted(confirmation: confirmation)
        self.fieldErrors = [:]
        self.formError = nil
    }

    func markFailed(_ message: String = L10n.formSubmitFailed.string) {
        self.phase = .failed(message)
    }

    /// Applies a 422 (or validation) response — per-field messages land under inputs;
    /// unmatched params and a non-empty envelope message become the card banner.
    func applyServerErrors(params: [ValidationError], formMessage: String?) {
        self.phase = .editing
        let applied = FormServerErrors.apply(
            params: params,
            formMessage: formMessage,
            knownFieldKeys: Set(self.form.fields.map(\.key))
        )
        self.fieldErrors = applied.fieldErrors
        self.formError = applied.formError
    }
}
