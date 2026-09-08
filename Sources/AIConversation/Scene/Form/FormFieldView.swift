//
//  FormFieldView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Renders one visible ``FormField`` — text / email / tel / textarea, or delegates to
/// dropdown / file siblings. Disabled when the form is read-only or submitting.
///
/// Accessibility: the control carries the field label (VoiceOver reads it as the input's name,
/// not just the placeholder); a required field adds the requirement as its hint and the
/// visible `*` is hidden from the rotor.
struct FormFieldView: View {

    @Environment(\.appearance) private var appearance

    let field: FormField
    @Binding var value: String
    let focus: FocusState<String?>.Binding
    let focusID: String
    let error: String?
    let isEnabled: Bool
    let offersAttachments: Bool
    let pickedFile: PendingAttachment?
    let onPickFile: () -> Void
    let onRemoveFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(1)) {
            HStack(spacing: 2) {
                Text(self.field.label)
                if self.field.required {
                    Text(verbatim: "*")
                        .foregroundStyle(self.appearance.theme.destructive)
                        .accessibilityHidden(true)
                }
            }
            .font(self.appearance.font(size: 13, weight: .bold))
            .foregroundStyle(self.appearance.theme.primaryText)
            // Text inputs and the dropdown carry the label themselves; the file field's own
            // buttons ("Add photo" / "Remove photo") are the actions, so its header stays spoken.
            .accessibilityHidden(self.field.type != .file)

            self.control

            if let error {
                Text(error)
                    .font(self.appearance.font(size: 11))
                    .foregroundStyle(self.appearance.theme.destructive)
            }
        }
        .disabled(!self.isEnabled)
    }

    @ViewBuilder
    private var control: some View {
        switch self.field.type {
        case .dropdown:
            FormDropdownField(
                label: self.field.label,
                options: self.field.options,
                selection: self.$value,
                isEnabled: self.isEnabled
            )
            .accessibilityIdentifier("form.field.\(self.field.key)")
        case .file:
            FormFileField(
                picked: self.pickedFile,
                offersAttachments: self.offersAttachments,
                isEnabled: self.isEnabled,
                onPick: self.onPickFile,
                onRemove: self.onRemoveFile
            )
        case .textarea:
            TextField(
                self.field.placeholder ?? "",
                text: self.$value,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .focused(self.focus, equals: self.focusID)
            .lineLimit(3...6)
            .font(self.appearance.font(size: 15))
            .foregroundStyle(self.appearance.theme.inputText)
            .padding(self.appearance.spacing.units(2))
            .background(self.appearance.theme.inputBackground ?? self.appearance.theme.background)
            .border(self.borderColor, width: 1)
            .accessibilityLabel(self.field.label)
            .accessibilityHint(self.field.required ? L10n.formRequired.string : "")
                .accessibilityIdentifier("form.field.\(self.field.key)")
#if os(iOS)
            .textInputAutocapitalization(.sentences)
#endif
        case .text, .email, .tel:
            TextField(self.field.placeholder ?? "", text: self.$value)
                .textFieldStyle(.plain)
                .focused(self.focus, equals: self.focusID)
                .font(self.appearance.font(size: 15))
                .foregroundStyle(self.appearance.theme.inputText)
                .padding(self.appearance.spacing.units(2))
                .background(self.appearance.theme.inputBackground ?? self.appearance.theme.background)
                .border(self.borderColor, width: 1)
                .accessibilityLabel(self.field.label)
                .accessibilityHint(self.field.required ? L10n.formRequired.string : "")
                .accessibilityIdentifier("form.field.\(self.field.key)")
#if os(iOS)
                .keyboardType(self.keyboardType)
                .textContentType(self.contentType)
                .textInputAutocapitalization(self.field.type == .email ? .never : .words)
                .autocorrectionDisabled(self.field.type == .email || self.field.type == .tel)
#endif
        }
    }

    private var borderColor: Color {
        if self.error != nil {
            return self.appearance.theme.destructive
        }
        return self.appearance.theme.inputBorder ?? self.appearance.theme.botSurfaceBorder ?? .clear
    }

#if os(iOS)
    private var keyboardType: UIKeyboardType {
        switch self.field.type {
        case .email: .emailAddress
        case .tel: .phonePad
        default: .default
        }
    }

    private var contentType: UITextContentType? {
        switch self.field.type {
        case .email: .emailAddress
        case .tel: .telephoneNumber
        case .text where self.field.key == "name": .name
        default: nil
        }
    }
#endif
}
