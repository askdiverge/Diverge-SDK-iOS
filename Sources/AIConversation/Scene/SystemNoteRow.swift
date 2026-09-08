//
//  SystemNoteRow.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Centred, muted copy for wire `role: system` history — distinct from assistant bubbles and
/// SDK-local livechat boundary notes.
struct SystemNoteRow: View {

    @Environment(\.appearance) private var appearance

    let responses: [ChatResponse]

    var body: some View {
        Text(self.copy)
            .font(self.appearance.font(size: 12))
            .foregroundStyle(self.appearance.theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, self.appearance.spacing.units(2))
            .accessibilityIdentifier("conversation.systemNote")
    }

    private var copy: String {
        self.responses.compactMap { response -> String? in
            guard case .text(let text) = response else { return nil }
            let trimmed = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: "\n")
    }
}
