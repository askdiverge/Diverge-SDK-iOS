//
//  FormDropdownField.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// A single-select dropdown for a ``FormField`` of type `dropdown`. An optional field's answer
/// can be cleared again, which also hides the fields that depend on it.
struct FormDropdownField: View {

    @Environment(\.appearance) private var appearance

    /// The field's label — spoken by VoiceOver; the visible label is the sibling `Text`.
    let label: String
    let options: [String]
    let required: Bool
    @Binding var selection: String
    let isEnabled: Bool

    var body: some View {
        Menu {
            if !self.required, !self.selection.isEmpty {
                Button(L10n.formClearSelection.string) {
                    self.selection = ""
                }
            }
            ForEach(self.options, id: \.self) { option in
                Button(option) {
                    self.selection = option
                }
            }
        } label: {
            HStack {
                Text(self.selection.isEmpty ? L10n.formSelectOption.string : self.selection)
                    .font(self.appearance.font(size: 15))
                    .foregroundStyle(
                        self.selection.isEmpty
                            ? self.appearance.theme.inputText.opacity(0.5)
                            : self.appearance.theme.inputText
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.appearance.theme.primaryText.opacity(0.6))
            }
            .padding(self.appearance.spacing.units(2))
            .frame(minHeight: self.appearance.spacing.units(11))
            .background(self.appearance.theme.inputBackground ?? self.appearance.theme.background)
            .border(
                self.appearance.theme.inputBorder ?? self.appearance.theme.botSurfaceBorder ?? .clear,
                width: 1
            )
        }
        .disabled(!self.isEnabled)
        .buttonStyle(.plain)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.selection.isEmpty ? L10n.formSelectOption.string : self.selection)
        .accessibilityHint(self.required ? L10n.formRequired.string : "")
    }
}
