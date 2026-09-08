//
//  LivechatWaitingFormView.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Session-scoped “Add details for the agent” card while livechat status is `waiting`.
///
/// Field order matches web (`SessionForm`): title, description, fields, error.
/// Save lives in ``ChatView`` chrome above the composer so it stays on screen.
struct LivechatWaitingFormView: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: WaitingFormModel
    let focus: FocusState<String?>.Binding

    private var theme: ChatAppearance.Theme { self.appearance.theme }
    private var spacing: ChatAppearance.Spacing { self.appearance.spacing }

    var body: some View {
        VStack(alignment: .leading, spacing: self.spacing.units(3)) {
            Text(L10n.sessionFormTitle)
                .font(self.appearance.font(size: 15, weight: .bold))
                .foregroundStyle(self.theme.primaryText)

            Text(L10n.sessionFormDescription)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.theme.secondaryText)
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
            }

            if let banner = self.model.bannerError {
                Text(banner.message)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.theme.destructive)
                    .accessibilityIdentifier(banner.accessibilityID)
            }
        }
        .padding(self.spacing.units(4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.theme.background)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.theme.outline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, self.spacing.units(4))
        .padding(.vertical, self.spacing.units(2))
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

/// Save + “Details saved” — pinned above the composer so a tall field list does not hide it.
struct LivechatWaitingFormSaveChrome: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: WaitingFormModel
    let onSave: () -> Void

    private var theme: ChatAppearance.Theme { self.appearance.theme }
    private var spacing: ChatAppearance.Spacing { self.appearance.spacing }

    var body: some View {
        HStack(spacing: self.spacing.units(3)) {
            Button(action: self.onSave) {
                AccentCapsuleLabel(
                    title: self.model.isSaving
                        ? L10n.sessionFormSaving.string
                        : L10n.sessionFormSave.string,
                    isBusy: self.model.isSaving
                )
            }
            .buttonStyle(.plain)
            .disabled(!self.model.canSave)
            .accessibilityIdentifier("livechat.waitingForm.save")

            if self.model.isSaved {
                Text(L10n.sessionFormSaved)
                    .font(self.appearance.font(size: 13))
                    .foregroundStyle(self.theme.secondaryText)
                    .accessibilityIdentifier("livechat.waitingForm.saved")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, self.spacing.units(4))
        .padding(.vertical, self.spacing.units(2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(self.theme.background)
    }
}
