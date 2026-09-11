//
//  AccentCapsuleLabel.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// The accent-filled pill used as a button label throughout the conversation: history retry,
/// the upload-prompt card, form "Add photo" and form Submit. One place for the 44 pt minimum
/// height, the accent foreground and the capsule fill.
struct AccentCapsuleLabel: View {

    @Environment(\.appearance) private var appearance

    let title: String
    /// Optional leading glyph.
    var symbol: Image?
    /// Stretch to the container's width (form Submit) instead of hugging the title.
    var fillsWidth = false
    /// Shows a spinner in place of the glyph while an action is in flight.
    var isBusy = false
    /// Optional fill; defaults to the theme accent.
    var background: Color?
    /// Whether the title uses bold weight. Defaults to `true`.
    var bold = true

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            if self.isBusy {
                ProgressView()
                    .tint(self.appearance.theme.accentForeground)
            } else if let symbol {
                symbol.font(.system(size: 14))
            }
            Text(self.title)
                .font(self.appearance.font(size: 13, weight: self.bold ? .bold : .regular))
        }
        .foregroundStyle(self.appearance.theme.accentForeground)
        .padding(.horizontal, self.appearance.spacing.units(3))
        .frame(maxWidth: self.fillsWidth ? .infinity : nil)
        .frame(minHeight: self.appearance.spacing.units(11))
        .background(self.background ?? self.appearance.theme.accent, in: Capsule())
    }
}
