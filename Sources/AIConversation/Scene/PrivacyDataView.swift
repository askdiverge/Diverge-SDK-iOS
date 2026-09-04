//
//  PrivacyDataView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-29.
//

import SwiftUI

/// The Privacy & Data menu
struct PrivacyDataView: View {

    @Environment(\.appearance) private var appearance

    let onPrivacy: () -> Void
    let onDelete: () -> Void

    private var theme: ChatAppearance.Theme {
        self.appearance.theme
    }

    private var spacing: ChatAppearance.Spacing {
        self.appearance.spacing
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
            self.privacyRow
            self.deleteRow
        }
        .frame(maxWidth: .infinity)
        .background(self.theme.background)
    }

    private var privacyRow: some View {
        self.row(
            icon: ChatAppearance.Symbol.privacy,
            title: L10n.privacyPolicy.string,
            tint: self.theme.primaryText,
            accessory: ChatAppearance.Symbol.externalLink,
            action: self.onPrivacy
        )
    }

    private var deleteRow: some View {
        self.row(
            icon: ChatAppearance.Symbol.delete,
            title: L10n.privacyDeleteEntry.string,
            tint: self.theme.destructive,
            accessory: ChatAppearance.Symbol.disclosure,
            action: self.onDelete
        )
    }

    private func row(
        icon: Image,
        title: String,
        tint: Color,
        accessory: Image,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: self.spacing.units(2)) {
                icon
                    .font(.system(size: 20))
                    .foregroundStyle(tint)

                Text(title)
                    .font(self.appearance.font(size: 17))
                    .foregroundStyle(tint)

                Spacer(minLength: 0)

                accessory
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(self.theme.primaryText)
            }
            .frame(minHeight: self.spacing.units(11))
            .padding(.leading, self.spacing.units(6))
            .padding(.trailing, self.spacing.units(4))
            .padding(.vertical, self.spacing.units(3))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
