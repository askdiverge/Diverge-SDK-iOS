//
//  WaitingFormModel.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Draft + save state for the livechat waiting-room session form.
///
/// Unlike ``FormSubmissionModel``, a successful save keeps the fields filled and shows a
/// "Details saved" caption — it does not collapse to a confirmation card. A save sends only the
/// non-empty values of visible fields: the server keeps every value it stored, so a value can be
/// replaced but not removed.
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
    /// Fields the card can't show are omitted — see ``cardFields(from:)``.
    let form: ConversationForm
    let definition: ChatFormDefinition

    var values: [String: String] = [:]
    /// The values the session holds, by key.
    private var savedValues: [String: String] = [:]
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

    /// The draft differs from what the session holds, and no save is in flight.
    var canSave: Bool {
        !self.isSaving && self.valuesForPatch().contains { key, value in value != (self.savedValues[key] ?? "") }
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

    /// The fields the card shows, or nil when it has none or no save could succeed. `PATCH …/values`
    /// takes strings and requires every required field of the form, whether or not a condition
    /// shows it. So a required `file` field, a required field of a type this SDK has no control
    /// for, or a required field behind a condition means no card; optional fields of the first two
    /// kinds are left out of it.
    static func cardFields(from definition: ChatFormDefinition) -> [FormField]? {
        let unsavable = definition.fields.contains { field in
            field.required && (field.type == .file || field.type == .unknown || !field.visibleWhen.isEmpty)
        }
        let fields = definition.fields.filter { $0.type != .file && $0.type != .unknown }
        return unsavable || fields.isEmpty ? nil : fields
    }

    init(definition: ChatFormDefinition, sessionValues: [ChatSessionValue] = []) {
        self.definition = definition
        let fields = Self.cardFields(from: definition) ?? []
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
        self.savedValues = saved
    }

    func setValue(_ value: String, for key: String) {
        self.values[key] = value
        self.fieldErrors[key] = nil
        if case .failed = self.phase { self.phase = .editing }
        if case .saved = self.phase { self.phase = .editing }
    }

    @discardableResult
    func validate() -> Bool {
        let result = FormValidator.validate(form: self.form, values: self.values, files: [], offersFileFields: false)
        self.fieldErrors = result.fieldErrors
        self.formError = result.formError
        return result.isValid
    }

    /// The `PATCH` body: the trimmed, non-empty values of visible fields. A field the visitor
    /// emptied or a condition now hides isn't sent, and the server keeps what it stored for it.
    func valuesForPatch() -> [String: String] {
        var out: [String: String] = [:]
        for field in FormValidator.visibleFields(of: self.form, values: self.values) {
            let trimmed = (self.values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Takes the session the save returned as the saved state: the card's fields show its
    /// values, including any the visitor emptied, since the server keeps those.
    func markSaved(_ session: ChatSessionState) {
        let saved = Dictionary(session.values.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        for field in self.form.fields {
            self.values[field.key] = saved[field.key] ?? ""
        }
        self.savedValues = saved
        self.phase = .saved
        self.fieldErrors = [:]
        self.formError = nil
    }

    func markFailed(_ message: String = L10n.sessionFormFailed.string) {
        self.phase = .failed(message)
        self.formError = nil
    }

    /// Applies a validation envelope — errors for visible fields under their inputs; anything else
    /// shows the SDK's send-failed copy on the card banner.
    func applyServerErrors(params: [ValidationError]) {
        self.phase = .editing
        let applied = FormServerErrors.apply(
            params: params,
            knownFieldKeys: Set(FormValidator.visibleFields(of: self.form, values: self.values).map(\.key))
        )
        self.fieldErrors = applied.fieldErrors
        self.formError = applied.formError
    }
}
