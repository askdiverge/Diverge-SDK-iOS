//
//  FormValidator.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import AIConversationEngine

/// Pure validation for a ``ConversationForm`` draft. Hidden fields (whose `visible_when`
/// conditions do not match) are never required and never counted toward `min_filled_fields`.
enum FormValidator {

    /// Contract cap on the ticket `email` (`@maxLength(254)`); the server rejects longer values.
    static let maxEmailLength = 254

    /// Per-field and form-level validation outcome.
    struct Result: Equatable {
        /// Key → localised error for each failing field.
        var fieldErrors: [String: String]
        /// Form-level error (e.g. `min_filled_fields`), else `nil`.
        var formError: String?

        var isValid: Bool { self.fieldErrors.isEmpty && self.formError == nil }
    }

    /// Visible fields in definition order — the single visibility API shared by the card, the
    /// validator and the request builder.
    ///
    /// Mirrors the server's `computeVisibleFieldKeys`: one ordered forward pass where a
    /// condition matches only if the field it references is *already visible* and holds the
    /// trimmed value. Hiding a parent therefore cascades to every dependent even when the
    /// dependent's own condition would still match a stale answer, and a condition that points
    /// at a later (or unknown) field never matches.
    static func visibleFields(of form: ConversationForm, values: [String: String]) -> [FormField] {
        var visible: [FormField] = []
        var visibleKeys: Set<String> = []
        for field in form.fields {
            let shown = field.visibleWhen.allSatisfy { condition in
                guard visibleKeys.contains(condition.field) else { return false }
                let answer = (values[condition.field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                switch condition.operator {
                case .equals:
                    return answer == condition.value
                case .unknown:
                    return false
                }
            }
            if shown {
                visible.append(field)
                visibleKeys.insert(field.key)
            }
        }
        return visible
    }

    /// The first visible required field this app can't fill — a `file` field while photo attach
    /// isn't offered for this form (see ``validate(form:values:files:offersFileFields:)``), or a
    /// type it doesn't know. While one is visible the form can't be completed.
    static func blockingField(
        of form: ConversationForm,
        values: [String: String],
        offersFileFields: Bool
    ) -> FormField? {
        let fileFieldsFillable = offersFileFields && form.acceptsFileFields
        return Self.visibleFields(of: form, values: values).first { field in
            field.required && (field.type == .unknown || (field.type == .file && !fileFieldsFillable))
        }
    }

    /// Validates the draft. `files` holds keys that currently have a picked file.
    /// Error strings are SDK-owned (the API supplies none on the client path).
    ///
    /// A `file` field is filled through the photo picker, so it takes an answer only while the host
    /// offers photo attach (`offersFileFields`) and the form kind has a wire slot for it
    /// (``ConversationForm/acceptsFileFields``). A `.unknown` field never takes one. A required
    /// field that can't take an answer makes the form unavailable (see
    /// ``blockingField(of:values:offersFileFields:)``). A contact or custom form needs at least one
    /// answer, since its action can't be sent empty.
    static func validate(
        form: ConversationForm,
        values: [String: String],
        files: Set<String>,
        offersFileFields: Bool
    ) -> Result {
        var fieldErrors: [String: String] = [:]
        let visible = Self.visibleFields(of: form, values: values)
        let fileFieldsFillable = offersFileFields && form.acceptsFileFields

        for field in visible {
            switch field.type {
            case .unknown:
                break
            case .file:
                if field.required, fileFieldsFillable, !files.contains(field.key) {
                    fieldErrors[field.key] = L10n.formRequired.string
                }
            case .email:
                let trimmed = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if field.required, trimmed.isEmpty {
                    fieldErrors[field.key] = L10n.formRequired.string
                } else if !trimmed.isEmpty,
                          !Self.isValidEmail(trimmed) || trimmed.count > Self.maxEmailLength {
                    fieldErrors[field.key] = L10n.formInvalidEmail.string
                }
            case .text, .tel, .textarea, .dropdown:
                let trimmed = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if field.required, trimmed.isEmpty {
                    fieldErrors[field.key] = L10n.formRequired.string
                }
            }
        }

        var formError: String?
        let min = Self.minimumAnswers(for: form)
        if min > 0 {
            let filled = visible.reduce(into: 0) { count, field in
                switch field.type {
                case .file:
                    if fileFieldsFillable, files.contains(field.key) { count += 1 }
                case .unknown:
                    break
                default:
                    let trimmed = (values[field.key] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { count += 1 }
                }
            }
            if filled < min {
                formError = L10n.formMinFilled(min).string
            }
        }
        if Self.blockingField(of: form, values: values, offersFileFields: offersFileFields) != nil {
            formError = L10n.formUnavailable.string
        }

        return Result(fieldErrors: fieldErrors, formError: formError)
    }

    /// Answers a submit needs: the form's `min_filled_fields`, and at least one for a contact or
    /// custom form, whose action the API rejects empty. A ticket's own required fields cover it.
    private static func minimumAnswers(for form: ConversationForm) -> Int {
        switch form.kind {
        case .supportTicket: form.minFilledFields
        case .contact, .custom: max(1, form.minFilledFields)
        }
    }

    /// Contract email pattern: at least one non-space/@ before and after `@`, with a dot in the domain.
    static func isValidEmail(_ value: String) -> Bool {
        // Matches the TypeSpec `@pattern("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")`.
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
