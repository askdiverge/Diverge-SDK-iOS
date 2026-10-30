//
//  FormActionBuilder.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import AIConversationEngine

/// Builds a ``SubmitActionRequest`` from a filled ``ConversationForm``. Hidden fields are
/// excluded (same forward pass as ``FormValidator/visibleFields(of:values:)``). Ticket
/// attachments ride as a separate array (not field-keyed).
enum FormActionBuilder {

    /// Builds the request. Returns `nil` when nothing submittable remains — an empty contact /
    /// custom payload, or a support ticket missing one of `name` / `email` / `message` among
    /// its visible fields. Validation should have caught that earlier; this is a defensive guard.
    ///
    /// - Parameters:
    ///   - files: Picked files keyed by `FormField.key` (custom-form file fields).
    ///   - ticketAttachments: Ticket-level attachments (support-ticket forms only).
    static func build(
        form: ConversationForm,
        values: [String: String],
        files: [String: OutgoingAttachment],
        ticketAttachments: [OutgoingAttachment]
    ) -> SubmitActionRequest? {
        let visible = FormValidator.visibleFields(of: form, values: values)
        let answers = Self.textAnswers(of: visible, values: values)

        switch form.kind {
        case .contact:
            // `ContactFormAction.fields` is a string map — the wire has no slot for files.
            guard !answers.isEmpty else { return nil }
            return SubmitActionRequest(partId: form.partId, action: .contactForm(fields: answers))

        case .supportTicket:
            guard let name = answers["name"], let email = answers["email"], let message = answers["message"]
            else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .supportTicket(
                    name: name,
                    email: email,
                    message: message,
                    attachments: ticketAttachments.isEmpty ? nil : ticketAttachments
                )
            )

        case .custom(let formId, _, _, _):
            var fileValues: [String: OutgoingAttachment] = [:]
            for field in visible where field.type == .file {
                if let file = files[field.key] {
                    fileValues[field.key] = file
                }
            }
            guard !answers.isEmpty || !fileValues.isEmpty else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .formSubmission(
                    formId: formId,
                    values: answers.isEmpty ? nil : answers,
                    files: fileValues.isEmpty ? nil : fileValues
                )
            )
        }
    }

    /// The trimmed, non-empty answers of the visible non-file fields, keyed by `FormField.key`.
    private static func textAnswers(of visible: [FormField], values: [String: String]) -> [String: String] {
        var answers: [String: String] = [:]
        for field in visible where field.type != .file {
            let trimmed = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                answers[field.key] = trimmed
            }
        }
        return answers
    }
}
