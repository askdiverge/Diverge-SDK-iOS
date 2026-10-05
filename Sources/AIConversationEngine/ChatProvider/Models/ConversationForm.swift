//
//  ConversationForm.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Display-oriented form — the three wire markers collapse here so the UI and the submit
/// builder each switch on one enum instead of three near-identical paths.
///
/// `submit_actions` / `submit_rules` stay on the server; the client only echoes `partId`.
package struct ConversationForm: Sendable, Equatable {

    package enum Kind: Sendable, Equatable {
        case contact
        case supportTicket(attachmentsAccepted: Bool, maxAttachmentSizeBytes: Int)
        case custom(formId: String, name: String?, confirmationText: String?, minFilledFields: Int)
    }

    package let partId: String
    package let kind: Kind
    package let fields: [FormField]

    package init(partId: String, kind: Kind, fields: [FormField]) {
        self.partId = partId
        self.kind = kind
        self.fields = fields
    }

    /// Normalises a contact-form marker.
    package static func contact(_ marker: ShowContactForm) -> ConversationForm {
        .init(partId: marker.partId, kind: .contact, fields: marker.fields)
    }

    /// The marker field keys a `support_ticket` action carries, as its `name`, `email` and
    /// `message`.
    package static let supportTicketFieldKeys: Set<String> = ["name", "email", "message"]

    /// Normalises a support-ticket marker to the fields the `support_ticket` action carries.
    /// `nil` when the marker lacks one of them; the turn then renders without the card.
    package static func supportTicket(_ marker: ShowSupportTicket) -> ConversationForm? {
        let fields = marker.fields.filter { Self.supportTicketFieldKeys.contains($0.key) }
        guard Set(fields.map(\.key)) == Self.supportTicketFieldKeys else { return nil }
        return .init(
            partId: marker.partId,
            kind: .supportTicket(
                attachmentsAccepted: marker.attachmentsAccepted,
                maxAttachmentSizeBytes: marker.maxAttachmentSizeBytes
            ),
            fields: fields
        )
    }

    /// Normalises a custom-form marker.
    package static func custom(_ marker: ShowForm) -> ConversationForm {
        .init(
            partId: marker.partId,
            kind: .custom(
                formId: marker.formId,
                name: marker.name,
                confirmationText: marker.confirmationText,
                minFilledFields: marker.minFilledFields
            ),
            fields: marker.fields
        )
    }

    /// Title shown above the fields — a named custom form's name; `nil` for the other kinds and
    /// an unnamed custom form, which use SDK copy.
    package var displayName: String? {
        if case .custom(_, let name, _, _) = self.kind { return name }
        return nil
    }

    /// Optional confirmation the server may return; custom forms may also carry one inline.
    package var confirmationText: String? {
        if case .custom(_, _, let text, _) = self.kind { return text }
        return nil
    }

    /// Minimum filled (visible, non-empty) fields required before submit — only custom forms set this.
    package var minFilledFields: Int {
        if case .custom(_, _, _, let min) = self.kind { return min }
        return 0
    }
}
