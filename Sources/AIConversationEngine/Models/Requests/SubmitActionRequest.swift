//
//  SubmitActionRequest.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Request body for `POST /api/v1/chat/actions`.
///
/// Encoded with a **strategy-free** encoder and explicit snake_case `CodingKeys`. The
/// default `convertToSnakeCase` encoder would rewrite dictionary keys in `fields` /
/// `values` / `files` (e.g. `orderNumber` → `order_number`), which the server would not
/// recognise. Attachments encode as the wire `Attachment` via ``OutgoingAttachment``.
/// [API ref](https://docs.dialoge.ai/api#operation/Actions_submit)
package struct SubmitActionRequest: Encodable, Sendable, Equatable {

    package let partId: String
    package let action: Action

    package init(partId: String, action: Action) {
        self.partId = partId
        self.action = action
    }

    private enum CodingKeys: String, CodingKey {
        case partId = "part_id"
        case action
    }
}

extension SubmitActionRequest {

    /// Discriminated on `type`. Hidden fields must be excluded before building.
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

        private enum CodingKeys: String, CodingKey {
            case type, fields, name, email, message, attachments
            case formId = "form_id"
            case values, files
        }

        package func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .contactForm(let fields):
                try container.encode("contact_form", forKey: .type)
                try container.encode(fields, forKey: .fields)

            case .supportTicket(let name, let email, let message, let attachments):
                try container.encode("support_ticket", forKey: .type)
                try container.encode(name, forKey: .name)
                try container.encode(email, forKey: .email)
                try container.encode(message, forKey: .message)
                try container.encodeIfPresent(attachments, forKey: .attachments)

            case .formSubmission(let formId, let values, let files):
                try container.encode("form_submission", forKey: .type)
                try container.encodeIfPresent(formId, forKey: .formId)
                try container.encodeIfPresent(values, forKey: .values)
                try container.encodeIfPresent(files, forKey: .files)
            }
        }
    }
}

/// Success body for `POST /api/v1/chat/actions`.
///
/// When the form's server `submit_actions` include `start_livechat`, the backend also returns
/// `livechat_session` (same shape as handover). The SDK starts polling from that signal and
/// does **not** call `POST /livechat/handover`.
package struct SubmitActionResponse: Decodable, Sendable, Equatable {

    package let submissionId: String
    package let confirmationText: String?
    /// Present when the server started or reused a livechat session for this submit.
    package let livechatSession: LivechatSessionHint?

    package init(
        submissionId: String,
        confirmationText: String? = nil,
        livechatSession: LivechatSessionHint? = nil
    ) {
        self.submissionId = submissionId
        self.confirmationText = confirmationText
        self.livechatSession = livechatSession
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.submissionId = try container.decode(String.self, forKey: .submissionId)
        // Missing, `null` and malformed all become nil — the SDK has its own fallback copy.
        self.confirmationText = try? container.decodeIfPresent(String.self, forKey: .confirmationText)
        self.livechatSession = try? container.decodeIfPresent(LivechatSessionHint.self, forKey: .livechatSession)
    }

    private enum CodingKeys: String, CodingKey {
        case submissionId, confirmationText, livechatSession
    }
}

/// Minimal `livechat_session` from `POST /actions` — only `status` is required to start polling.
package struct LivechatSessionHint: Decodable, Sendable, Equatable {

    package let status: LivechatState.Status

    package init(status: LivechatState.Status) {
        self.status = status
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decodeIfPresent(LivechatState.Status.self, forKey: .status) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case status
    }

    /// Whether the SDK should attach the livechat poller after form submit.
    package var shouldAdoptPoller: Bool {
        self.status == .waiting || self.status == .active
    }
}
