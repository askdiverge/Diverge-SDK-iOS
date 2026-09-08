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
        files: [String: OutgoingAttachment] = [:],
        ticketAttachments: [OutgoingAttachment] = []
    ) -> SubmitActionRequest? {
        let visible = FormValidator.visibleFields(of: form, values: values)

        switch form.kind {
        case .contact:
            // `ContactFormAction.fields` is a string map — the wire has no slot for files.
            var fields: [String: String] = [:]
            for field in visible where field.type != .file {
                let trimmed = Self.trimmed(values[field.key])
                if !trimmed.isEmpty {
                    fields[field.key] = trimmed
                }
            }
            guard !fields.isEmpty else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .contactForm(fields: fields)
            )

        case .supportTicket:
            let name = Self.trimmed(values["name"])
            let email = Self.trimmed(values["email"])
            let message = Self.trimmed(values["message"])
            guard !name.isEmpty, !email.isEmpty, !message.isEmpty else { return nil }
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
            var textValues: [String: String] = [:]
            var fileValues: [String: OutgoingAttachment] = [:]
            for field in visible {
                switch field.type {
                case .file:
                    if let file = files[field.key] {
                        fileValues[field.key] = file
                    }
                default:
                    let trimmed = Self.trimmed(values[field.key])
                    if !trimmed.isEmpty {
                        textValues[field.key] = trimmed
                    }
                }
            }
            guard !textValues.isEmpty || !fileValues.isEmpty else { return nil }
            return SubmitActionRequest(
                partId: form.partId,
                action: .formSubmission(
                    formId: formId,
                    values: textValues.isEmpty ? nil : textValues,
                    files: fileValues.isEmpty ? nil : fileValues
                )
            )
        }
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
