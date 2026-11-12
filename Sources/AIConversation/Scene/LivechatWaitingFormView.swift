//
//  LivechatWaitingFormView.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Session-scoped “Add details for the agent” card while livechat status is `waiting`.
///
/// Field order matches web (`SessionForm`): title, description, fields. Save and its result live
/// in ``ChatView`` chrome above the composer so they stay on screen.
struct LivechatWaitingFormView: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: WaitingFormModel
    let focus: FocusState<String?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            Text(L10n.sessionFormTitle)
                .font(self.appearance.font(size: 15, weight: .bold))
                .foregroundStyle(self.appearance.theme.primaryText)

            Text(L10n.sessionFormDescription)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(self.visibleFields, id: \.key) { field in
                FormFieldView(
                    field: field,
                    value: self.binding(for: field.key),
                    focus: self.focus,
                    focusID: "waiting.\(field.key)",
                    error: self.model.fieldErrors[field.key],
                    isEnabled: !self.model.isSaving,
                    offersAttachments: false,
                    pickedFile: nil,
                    onPickFile: {},
                    onRemoveFile: {}
                )
                .id(field.key)
            }
        }
        .padding(self.appearance.spacing.units(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.appearance.theme.botSurface)
        .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.vertical, self.appearance.spacing.units(2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("livechat.waitingForm")
    }

    private var visibleFields: [FormField] {
        FormValidator.visibleFields(of: self.model.form, values: self.model.values)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { self.model.values[key] ?? "" },
            set: { self.model.setValue($0, for: key) }
        )
    }
}

/// Save and its result, “Details saved” or the error — pinned above the composer so a tall field
/// list hides neither. VoiceOver hears the result too.
struct LivechatWaitingFormSaveChrome: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: WaitingFormModel
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(3)) {
            Button(action: self.onSave) {
                AccentCapsuleLabel(
                    title: self.model.isSaving
                        ? L10n.sessionFormSaving.string
                        : L10n.sessionFormSave.string,
                    isBusy: self.model.isSaving
                )
            }
            .buttonStyle(.plain)
            .minimumTouchTarget()
            .disabled(!self.model.canSave)
            .accessibilityIdentifier("livechat.waitingForm.save")

            if self.model.isSaved {
                Text(L10n.sessionFormSaved)
                    .font(self.appearance.font(size: 13))
                    .foregroundStyle(self.appearance.theme.secondaryText)
                    .accessibilityIdentifier("livechat.waitingForm.saved")
            }
            if let banner = self.model.bannerError {
                Text(banner.message)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(banner.accessibilityID)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.vertical, self.appearance.spacing.units(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.appearance.theme.background)
        .onChange(of: self.model.isSaved) { _, isSaved in
            guard isSaved else { return }
            AccessibilityNotification.Announcement(L10n.sessionFormSaved.string).post()
        }
        .onChange(of: self.model.bannerError?.message) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}
