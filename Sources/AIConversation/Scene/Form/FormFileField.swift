//
//  FormFileField.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// A file-field control: an "Add photo" button, or a thumbnail chip with remove once picked.
/// When the host disabled attachments the affordance is replaced by explanatory copy instead
/// of vanishing, and a required one makes the form unavailable (see ``FormValidator``). The buttons
/// name their field to VoiceOver, because a form can hold several.
struct FormFileField: View {

    @Environment(\.appearance) private var appearance

    /// The field's label; `nil` for the support ticket's one attachment, which has no field.
    let fieldLabel: String?
    let isRequired: Bool
    let picked: PendingAttachment?
    let offersAttachments: Bool
    let isEnabled: Bool
    let onPick: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if !self.offersAttachments {
            Text(L10n.formAttachmentsDisabled.string)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.primaryText.opacity(0.6))
        } else if let picked {
            HStack(spacing: self.appearance.spacing.units(2)) {
                picked.thumbnail
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: self.appearance.spacing.units(11),
                        height: self.appearance.spacing.units(11)
                    )
                    .clipped()
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                Button(action: self.onRemove) {
                    ChatAppearance.Symbol.close
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(self.appearance.theme.primaryText)
                        .padding(self.appearance.spacing.units(2))
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .disabled(!self.isEnabled)
                .accessibilityLabel(Self.accessibilityLabel(L10n.formRemovePhoto.string, fieldLabel: self.fieldLabel))
            }
            .padding(self.appearance.spacing.units(2))
            .background(self.appearance.theme.inputBackground ?? self.appearance.theme.background)
            .border(
                self.appearance.theme.inputBorder ?? self.appearance.theme.botSurfaceBorder ?? .clear,
                width: 1
            )
        } else {
            Button(action: self.onPick) {
                AccentCapsuleLabel(title: L10n.formAddPhoto.string, symbol: ChatAppearance.Symbol.attach)
            }
            .buttonStyle(.plain)
            .disabled(!self.isEnabled)
            .accessibilityLabel(Self.accessibilityLabel(L10n.formAddPhoto.string, fieldLabel: self.fieldLabel))
            .accessibilityHint(self.isRequired ? L10n.formRequired.string : "")
        }
    }

    /// VoiceOver label for a button: the field, then what the button does.
    nonisolated static func accessibilityLabel(_ action: String, fieldLabel: String?) -> String {
        fieldLabel.map { "\($0): \(action)" } ?? action
    }
}
