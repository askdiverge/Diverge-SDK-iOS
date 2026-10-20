//
//  NoteRow.swift
//  AIConversation
//

import SwiftUI

/// Centred, muted note between turns: wire `role: system` copy, and the SDK's livechat notes.
struct NoteRow: View {

    @Environment(\.appearance) private var appearance

    let text: AttributedString
    let identifier: String

    var body: some View {
        Text(self.text)
            .font(self.appearance.font(size: 12))
            .foregroundStyle(self.appearance.theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, self.appearance.spacing.units(2))
            .accessibilityIdentifier(self.identifier)
    }
}
