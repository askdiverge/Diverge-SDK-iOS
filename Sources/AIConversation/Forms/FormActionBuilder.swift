//
//  FormActionBuilder.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import AIConversationEngine

/// Builds a ``SubmitActionRequest`` from a filled ``ConversationForm``. It sends the trimmed,
/// non-empty answers of visible fields (same forward pass as
/// ``FormValidator/visibleFields(of:values:)``); `file` fields render unavailable until photo
/// attach ships and carry no answer.
enum FormActionBuilder {

    /// Builds the request. Returns `nil` when nothing submittable remains — an empty contact /
    /// custom payload, or a support ticket missing one of `name` / `email` / `message` among
    /// its visible fields. Validation should have caught that earlier; this is a defensive guard.
    static func build(form: ConversationForm, values: [String: String]) -> SubmitActionRequest? {
        var answers: [String: String] = [:]
        for field in FormValidator.visibleFields(of: form, values: values) where field.type != .file {
            let trimmed = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                answers[field.key] = trimmed
            }
        }

        switch form.kind {
        case .contact:
            guard !answers.isEmpty else { return nil }
            return SubmitActionRequest(partId: form.partId, action: .contactForm(fields: answers))

        case .supportTicket:
            guard let name = answers["name"], let email = answers["email"], let message = answers["message"]
            else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .supportTicket(name: name, email: email, message: message, attachments: nil)
            )

        case .custom(let formId, _, _, _):
            guard !answers.isEmpty else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .formSubmission(formId: formId, values: answers, files: nil)
            )
        }
    }
}
