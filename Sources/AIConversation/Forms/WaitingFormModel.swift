//
//  WaitingFormModel.swift
//  AIConversation
//

import Foundation
import AIConversationEngine
import AIConversationCore

/// Draft + save state for the livechat waiting-room session form.
///
/// Unlike ``FormSubmissionModel``, a successful save keeps the fields filled and shows a
/// "Details saved" caption — it does not collapse to a confirmation card.
/// `file` fields are dropped: `PATCH …/values` is string-only (web `SessionForm` has no file
/// inputs) and `ConversationForm.custom` would otherwise require them.
@MainActor
@Observable
final class WaitingFormModel {

    enum Phase: Equatable {
        case editing
        case saving
        case saved
        case failed(String)
    }

    /// Synthetic ``ConversationForm`` so ``FormValidator`` / ``FormFieldView`` reuse works.
    /// File fields are omitted — see ``stringFields(from:)``.
    let form: ConversationForm
    let definition: ChatFormDefinition

    var values: [String: String] = [:]
    private(set) var fieldErrors: [String: String] = [:]
    private(set) var formError: String?
    private(set) var phase: Phase = .editing

    var isSaving: Bool {
        if case .saving = self.phase { return true }
        return false
    }

    var isSaved: Bool {
        if case .saved = self.phase { return true }
        return false
    }

    /// String fields the card can show. Empty → no card (file-only definition).
    var hasStringFields: Bool { !self.form.fields.isEmpty }

    /// At least one visible non-empty value (web `hasAnyValue`) and not currently saving.
    var canSave: Bool {
        guard !self.isSaving else { return false }
        let visible = FormValidator.visibleFields(of: self.form, values: self.values)
        return visible.contains { field in
            !(self.values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// One banner: transport failure wins over client validation. Distinct a11y ids.
    var bannerError: (message: String, accessibilityID: String)? {
        if case .failed(let message) = self.phase {
            return (message, "livechat.waitingForm.failed")
        }
        if let formError {
            return (formError, "livechat.waitingForm.validation")
        }
        return nil
    }

    /// Waiting forms are string PATCH bodies — skip `file` (PhotosPicker is not used here).
    static func stringFields(from definition: ChatFormDefinition) -> [FormField] {
        definition.fields.filter { $0.type != .file }
    }

    init(definition: ChatFormDefinition, sessionValues: [ChatSessionValue] = []) {
        self.definition = definition
        let fields = Self.stringFields(from: definition)
        self.form = ConversationForm(
            partId: "waiting:\(definition.formId)",
            kind: .custom(
                formId: definition.formId,
                name: definition.name ?? definition.formId,
                confirmationText: nil,
                minFilledFields: definition.minFilledFields
            ),
            fields: fields
        )
        let saved = Dictionary(
            sessionValues.map { ($0.key, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        self.values = Dictionary(
            fields.map { field in (field.key, saved[field.key] ?? "") },
            uniquingKeysWith: { _, last in last }
        )
    }

    func setValue(_ value: String, for key: String) {
        self.values[key] = value
        self.fieldErrors[key] = nil
        if case .failed = self.phase { self.phase = .editing }
        if case .saved = self.phase { self.phase = .editing }
    }

    @discardableResult
    func validate() -> Bool {
        let result = FormValidator.validate(form: self.form, values: self.values)
        self.fieldErrors = result.fieldErrors
        self.formError = result.formError
        return result.isValid
    }

    /// Non-empty trimmed values of **visible** string fields, ready for `PATCH`.
    func valuesForPatch() -> [String: String] {
        var out: [String: String] = [:]
        for field in FormValidator.visibleFields(of: self.form, values: self.values) {
            let trimmed = (self.values[field.key] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                out[field.key] = trimmed
            }
        }
        return out
    }

    func beginSaving() -> Bool {
        switch self.phase {
        case .saving:
            return false
        case .editing, .saved, .failed:
            self.phase = .saving
            self.formError = nil
            return true
        }
    }

    func markSaved() {
        self.phase = .saved
        self.fieldErrors = [:]
        self.formError = nil
    }

    func markFailed(_ message: String = L10n.sessionFormFailed.string) {
        self.phase = .failed(message)
        self.formError = nil
    }

    /// Applies a validation envelope — field errors under inputs; unmatched params and a
    /// leftover envelope message become the card banner.
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
