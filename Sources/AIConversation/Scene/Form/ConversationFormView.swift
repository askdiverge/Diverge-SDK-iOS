//
//  ConversationFormView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// In-conversation form card for contact / support-ticket / custom markers.
///
/// States: loading (a thin custom form's definition is being fetched), load failed (with a
/// retry), editing (fillable when `isEditable`), submitting, submitted (collapsed confirmation),
/// and read-only (older forms whose `part_id` the server would reject — the controls stay
/// visible but disabled and a caption says why).
struct ConversationFormView: View {

    @Environment(\.appearance) private var appearance

    let model: FormSubmissionModel
    /// The permanent rule: the form sits in the newest bot turn. `false` renders read-only.
    let isEditable: Bool
    /// Whether the host offers photo attach for file fields and ticket attachments.
    let offersAttachments: Bool
    /// The transient rule: streaming or a photo encode pauses the controls without the card
    /// turning read-only.
    let isBusy: Bool
    /// Shared focus for the form's text fields — see `ChatView.focusedFormField`.
    let focus: FocusState<String?>.Binding
    /// A text or dropdown answer changed: field key, new value.
    let onChange: (String, String) -> Void
    let onSubmit: () -> Void
    /// Fetches a thin custom form's definition again after the first fetch failed.
    let onReload: () -> Void
    /// Opens the photo picker for a custom-form file field (`FormField.key`).
    let onPickFile: (String) -> Void
    /// Clears a custom-form file field pick.
    let onRemoveFile: (String) -> Void
    /// Opens the photo picker for a support-ticket attachment.
    let onPickTicketAttachment: () -> Void
    /// Clears the support-ticket attachment.
    let onRemoveTicketAttachment: () -> Void

    var body: some View {
        Group {
            switch self.model.phase {
            case .submitted(let confirmation):
                self.confirmationCard(confirmation)
            default:
                self.editingCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel(for: self.model.form))
        .accessibilityHint(self.isEditable ? Self.accessibilityHint : L10n.formReadOnly.string)
    }

    private var editingCard: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            Text(self.title)
                .font(self.appearance.font(size: 15, weight: .bold))
                .foregroundStyle(self.appearance.theme.primaryText)
                .accessibilityAddTraits(.isHeader)

            if self.model.isHydrating {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if self.model.hydrationFailed {
                self.loadFailedRow
            } else if !self.model.isCompletable(offersFileFields: self.offersAttachments) {
                // Nothing the visitor can do here completes the form, so say so before Submit.
                Text(L10n.formUnavailable.string)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.primaryText.opacity(0.6))
                    .accessibilityIdentifier("form.unavailable")
            }

            ForEach(self.visibleFields, id: \.key) { field in
                FormFieldView(
                    field: field,
                    value: self.binding(for: field.key),
                    focus: self.focus,
                    focusID: "\(self.model.form.partId)/\(field.key)",
                    error: self.model.fieldErrors[field.key],
                    isEnabled: self.controlsEnabled,
                    offersAttachments: self.offersAttachments && self.model.form.acceptsFileFields,
                    pickedFile: self.model.files[field.key],
                    onPickFile: { self.onPickFile(field.key) },
                    onRemoveFile: { self.onRemoveFile(field.key) }
                )
            }

            if self.model.form.attachmentsAccepted {
                self.ticketAttachmentRow
            }

            if let formError = self.model.formError ?? self.failedMessage {
                Text(formError)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.destructive)
            }

            if self.isEditable {
                Button(action: self.onSubmit) {
                    AccentCapsuleLabel(
                        title: self.model.isSubmitting ? L10n.formSubmitting.string : L10n.formSubmit.string,
                        fillsWidth: true,
                        isBusy: self.model.isSubmitting
                    )
                }
                .buttonStyle(.plain)
                .disabled(!self.controlsEnabled || !self.model.hasFields || !self.model.isCompletable(offersFileFields: self.offersAttachments))
                .accessibilityLabel(L10n.formSubmit.string)
                .accessibilityIdentifier("form.submit")
            } else {
                // Sighted counterpart of the read-only VoiceOver hint.
                Text(L10n.formReadOnly.string)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.primaryText.opacity(0.6))
                    .accessibilityIdentifier("form.readOnly")
            }
        }
        .padding(self.appearance.spacing.units(3))
        .background(self.appearance.theme.botSurface)
        .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
        .onChange(of: self.errorAnnouncement) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// What VoiceOver hears after a failed submit: the card's error, else the first field error
    /// in field order, prefixed with that field's label.
    private var errorAnnouncement: String? {
        if let error = self.model.formError ?? self.failedMessage { return error }
        return self.visibleFields.lazy
            .compactMap { field in self.model.fieldErrors[field.key].map { "\(field.label): \($0)" } }
            .first
    }

    private var ticketAttachmentRow: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(1)) {
            Text(L10n.formAddPhoto.string)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(self.appearance.theme.primaryText)

            FormFileField(
                picked: self.model.ticketAttachments.first,
                offersAttachments: self.offersAttachments,
                isEnabled: self.controlsEnabled,
                onPick: self.onPickTicketAttachment,
                onRemove: self.onRemoveTicketAttachment
            )
        }
    }

    private var loadFailedRow: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            Text(L10n.formLoadFailed.string)
                .font(self.appearance.font(size: 12))
                .foregroundStyle(self.appearance.theme.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: self.onReload) {
                AccentCapsuleLabel(title: L10n.errorRetry.string)
            }
            .buttonStyle(.plain)
            .minimumTouchTarget()
            .disabled(!self.isEditable)
            .accessibilityIdentifier("form.reload")
        }
    }

    private func confirmationCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: self.appearance.spacing.units(2)) {
            ChatAppearance.Symbol.checkmark
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(self.appearance.theme.accent)
            Text(text)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(self.appearance.spacing.units(3))
        .background(self.appearance.theme.botSurface)
        .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
        .accessibilityLabel(text)
        .accessibilityIdentifier("form.confirmation")
    }

    private var title: String {
        Self.accessibilityLabel(for: self.model.form)
    }

    /// The visible fields this SDK has a control for.
    private var visibleFields: [FormField] {
        FormValidator.visibleFields(of: self.model.form, values: self.model.values)
            .filter { $0.type != .unknown }
    }

    private var controlsEnabled: Bool {
        self.isEditable && !self.model.isSubmitting && !self.isBusy
    }

    private var failedMessage: String? {
        if case .failed(let message) = self.model.phase { return message }
        return nil
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { self.model.values[key] ?? "" },
            set: { self.onChange(key, $0) }
        )
    }
}

// MARK: - Accessibility contract

extension ConversationFormView {

    /// The card's title, doubling as its VoiceOver label: a custom form's `name`, else SDK copy.
    nonisolated static func accessibilityLabel(for form: ConversationForm) -> String {
        if let name = form.displayName, !name.isEmpty { return name }
        switch form.kind {
        case .contact, .custom: return L10n.formContactTitle.string
        case .supportTicket: return L10n.formTicketTitle.string
        }
    }

    nonisolated static var accessibilityHint: String {
        L10n.formAccessibilityHint.string
    }
}
