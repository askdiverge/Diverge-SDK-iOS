//
//  SubmitActionRequest.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Request body for `POST /api/v1/chat/actions`. Field-keyed dictionaries keep the keys the
/// form defines; attachments encode as the wire `Attachment` via ``OutgoingAttachment``.
/// [API ref](https://docs.askdiverge.ai/api#tag/visitor-conversations/POST/api/v1/chat/actions)
package struct SubmitActionRequest: Encodable, Sendable, Equatable {

    /// The `part_id` of the marker that opened the form.
    package let partId: String
    /// What the visitor submitted.
    package let action: Action

    package init(partId: String, action: Action) {
        self.partId = partId
        self.action = action
    }
}

extension SubmitActionRequest {

    /// What the visitor submitted, discriminated on `type`. The backend routes the submission on
    /// `type` to the handler of the marker that opened the form. A case is added when the backend
    /// accepts a new action type and the SDK ships the form that produces it. Hidden fields must
    /// be excluded before building.
    package enum Action: Encodable, Sendable, Equatable {
        /// Contact / lead form — arbitrary key → string map.
        case contactForm(fields: [String: String])
        /// Support ticket — fixed name / email / message plus optional attachments.
        case supportTicket(
            name: String,
            email: String,
            message: String,
            attachments: [OutgoingAttachment]?
        )
        /// Custom form — text values and/or file values keyed by `FormField.key`.
        case formSubmission(
            formId: String?,
            values: [String: String]?,
            files: [String: OutgoingAttachment]?
        )

        /// `type` of a ``contactForm(fields:)`` submission.
        package static let contactFormType = "contact_form"
        /// `type` of a ``supportTicket(name:email:message:attachments:)`` submission.
        package static let supportTicketType = "support_ticket"
        /// `type` of a ``formSubmission(formId:values:files:)`` submission.
        package static let formSubmissionType = "form_submission"

        private enum CodingKeys: String, CodingKey {
            case type, fields, name, email, message, attachments, formId, values, files
        }

        package func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .contactForm(let fields):
                try container.encode(Self.contactFormType, forKey: .type)
                try container.encode(fields, forKey: .fields)

            case .supportTicket(let name, let email, let message, let attachments):
                try container.encode(Self.supportTicketType, forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(email, forKey: .email)
                try container.encode(message, forKey: .message)
                try container.encodeIfPresent(attachments, forKey: .attachments)

            case .formSubmission(let formId, let values, let files):
                try container.encode(Self.formSubmissionType, forKey: .type)
                try container.encodeIfPresent(formId, forKey: .formId)
                try container.encodeIfPresent(values, forKey: .values)
                try container.encodeIfPresent(files, forKey: .files)
            }
        }
    }
}
