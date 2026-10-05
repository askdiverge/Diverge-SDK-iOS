//
//  AccentCapsuleLabel.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// The accent-filled pill used as a button label on form Submit and Retry.
/// One place for the 44 pt minimum height, the accent foreground and the capsule fill.
struct AccentCapsuleLabel: View {

    @Environment(\.appearance) private var appearance

    let title: String
    /// Stretch to the container's width (form Submit) instead of hugging the title.
    var fillsWidth = false
    /// Shows a spinner before the title while an action is in flight.
    var isBusy = false

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            if self.isBusy {
                ProgressView()
                    .tint(self.appearance.theme.accentForeground)
            }
            Text(self.title)
                .font(self.appearance.font(size: 13, weight: .bold))
        }
        .foregroundStyle(self.appearance.theme.accentForeground)
        .padding(.horizontal, self.appearance.spacing.units(3))
        .frame(maxWidth: self.fillsWidth ? .infinity : nil)
        .frame(minHeight: self.appearance.spacing.units(11))
        .background(self.appearance.theme.accent, in: Capsule())
    }
}
