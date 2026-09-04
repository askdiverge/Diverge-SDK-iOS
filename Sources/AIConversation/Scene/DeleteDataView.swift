//
//  DeleteDataView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-30.
//

import SwiftUI

/// The delete-my-data confirmation sheet
struct DeleteDataView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.dismiss) private var dismiss

    let onConfirm: () -> Void

    @State private var isChecked = false
    @State private var showsValidation = false

    private var theme: ChatAppearance.Theme {
        self.appearance.theme
    }

    private var spacing: ChatAppearance.Spacing {
        self.appearance.spacing
    }

    /// The acknowledgement is missing — surfaced only once the user has attempted to delete.
    private var isInvalid: Bool {
        self.showsValidation && !self.isChecked
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.privacyTitle.string)
                .font(self.appearance.font(size: 17, weight: .bold))
                .foregroundStyle(self.theme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: self.spacing.units(11))
                .padding(.horizontal, self.spacing.units(2))
                .padding(.top, self.spacing.units(6))
            self.content
        }
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            self.footer
        }
        .background(self.theme.background)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: self.spacing.units(2)) {
            Text(L10n.deleteTitle)
                .font(self.appearance.font(size: 28, weight: .bold))

            Text(L10n.deleteMessage)
                .font(self.appearance.font(size: 17))

            // Base spacing pads both sides, so this opens the gap before the checkbox to 6.
            Spacer()
                .frame(height: self.spacing.units(2))

            Toggle(isOn: self.$isChecked) {
                Text(L10n.deleteConfirmation)
                    .font(self.appearance.font(size: 17))
            }
            .toggleStyle(CheckboxToggleStyle(isInvalid: self.isInvalid))
            .geometryGroup()

            if self.isInvalid {
                Text(L10n.deleteValidation)
                    .font(self.appearance.font(size: 11))
                    .foregroundStyle(self.theme.destructive)
            }
        }
        .foregroundStyle(self.theme.primaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, self.spacing.units(6))
    }

    private var footer: some View {
        HStack(spacing: self.spacing.units(2)) {
            self.leadingButton
            self.trailingButton
        }
        .padding([.top, .horizontal], self.spacing.units(6))
        .padding(.bottom, self.spacing.units(4))
        .background(self.theme.background)
    }

    private var leadingButton: some View {
        Button {
            self.dismiss()
        } label: {
            Text(L10n.deleteCancel)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(self.theme.primaryText)
                .padding(self.spacing.units(4))
                .frame(maxWidth: .infinity)
                .border(self.theme.outline, width: 1)
        }
        .buttonStyle(.plain)
    }

    private var trailingButton: some View {
        Button {
            self.confirmDelete()
        } label: {
            HStack(spacing: self.spacing.units(2)) {
                ChatAppearance.Symbol.delete
                    .font(.system(size: 14))

                Text(L10n.deleteConfirm)
                    .font(self.appearance.font(size: 13, weight: .bold))
            }
            .foregroundStyle(self.theme.accentForeground)
            .padding(self.spacing.units(4))
            .frame(maxWidth: .infinity)
            .background(self.theme.destructive)
        }
        .buttonStyle(.plain)
    }

    private func confirmDelete() {
        guard self.isChecked else {
            self.showsValidation = true
            return
        }
        self.showsValidation = false
        self.onConfirm()
    }
}
