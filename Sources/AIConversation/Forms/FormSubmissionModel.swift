//
//  FormSubmissionModel.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import AIConversationEngine

/// Per-form draft and submission state. ``ChatView/ViewModel`` holds one per `partId` and
/// changes it only through these methods.
struct FormSubmissionModel: Equatable {

    enum Phase: Equatable {
        case editing
        case submitting
        case submitted(confirmation: String)
        case failed(String)
    }

    private(set) var form: ConversationForm
    private(set) var values: [String: String] = [:]
    private(set) var fieldErrors: [String: String] = [:]
    private(set) var formError: String?
    private(set) var phase: Phase = .editing
    /// True while a thin `show_form` is being filled in from `GET …/forms/{id}`.
    private(set) var isHydrating = false
    /// True when that fetch failed; the card offers a retry.
    private(set) var hydrationFailed = false

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

    init(form: ConversationForm) {
        self.form = form
    }

    /// Server → inline marker copy → SDK default, skipping blank server text.
    static func confirmation(server: String?, form: ConversationForm) -> String {
        let trimmed = server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return form.confirmationText ?? L10n.formSubmittedDefault.string
    }

    /// Replaces empty inline fields with a definition fetched from `GET …/forms/{form_id}`.
    /// No-op when the draft already has fields, is submitted, or is not a custom form.
    mutating func applyHydratedDefinition(_ definition: ChatFormDefinition) {
        guard self.form.fields.isEmpty, !self.isSubmitted else { return }
        guard case .custom(let formId, let name, let confirmationText, let minFilledFields) = self.form.kind
        else { return }
        let definitionName = definition.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = definitionName?.isEmpty == false ? definitionName : name
        self.form = ConversationForm(
            partId: self.form.partId,
            kind: .custom(
                formId: formId,
                name: displayName,
                confirmationText: confirmationText,
                minFilledFields: definition.minFilledFields > 0
                    ? definition.minFilledFields
                    : minFilledFields
            ),
            fields: definition.fields
        )
        self.isHydrating = false
    }

    mutating func beginHydrating() {
        guard self.form.fields.isEmpty, !self.isSubmitted else { return }
        self.isHydrating = true
        self.hydrationFailed = false
    }

    mutating func failHydrating() {
        self.isHydrating = false
        self.hydrationFailed = true
    }

    /// Sets a text / dropdown answer and clears that field's error.
    mutating func setValue(_ value: String, for key: String) {
        self.values[key] = value
        self.fieldErrors[key] = nil
        if case .failed = self.phase { self.phase = .editing }
    }

    /// Runs client-side validation. Returns `true` when the draft is ready to submit.
    @discardableResult
    mutating func validate() -> Bool {
        let result = FormValidator.validate(form: self.form, values: self.values)
        self.fieldErrors = result.fieldErrors
        self.formError = result.formError
        return result.isValid
    }

    /// Builds the wire request from the current draft, or `nil` if the builder cannot.
    func buildRequest() -> SubmitActionRequest? {
        FormActionBuilder.build(form: self.form, values: self.values)
    }

    /// Enters `.submitting`. Returns `false` (and changes nothing) when a submit is already in
    /// flight or the form is already submitted.
    mutating func beginSubmitting() -> Bool {
        switch self.phase {
        case .submitting, .submitted:
            return false
        case .editing, .failed:
            self.phase = .submitting
            self.formError = nil
            return true
        }
    }

    mutating func markSubmitted(confirmation: String) {
        self.phase = .submitted(confirmation: confirmation)
        self.fieldErrors = [:]
        self.formError = nil
    }

    mutating func markFailed(_ message: String = L10n.formSubmitFailed.string) {
        self.phase = .failed(message)
    }

    /// Applies a 422 (or validation) response — messages for visible fields land under their
    /// inputs; the rest and a non-empty envelope message become the card banner.
    mutating func applyServerErrors(params: [ValidationError], formMessage: String?) {
        self.phase = .editing
        let applied = FormServerErrors.apply(
            params: params,
            formMessage: formMessage,
            knownFieldKeys: Set(FormValidator.visibleFields(of: self.form, values: self.values).map(\.key))
        )
        self.fieldErrors = applied.fieldErrors
        self.formError = applied.formError
    }
}
