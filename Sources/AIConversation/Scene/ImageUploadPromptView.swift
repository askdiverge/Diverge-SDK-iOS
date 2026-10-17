//
//  ImageUploadPromptView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Renders a `request_image_upload` marker as a card: prompt copy plus a single "Add photo"
/// control that opens the shared photo picker. No decline — the marker is a real history
/// part and would reappear on relaunch if dismissed locally.
struct ImageUploadPromptView: View {

    @Environment(\.appearance) private var appearance

    let onAttach: () -> Void

    var body: some View {
        Button(action: self.onAttach) {
            VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
                Text(L10n.imageUploadPrompt.string)
                    .font(self.appearance.font(size: 13))
                    .foregroundStyle(self.appearance.theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                AccentCapsuleLabel(
                    title: L10n.imageUploadAddPhoto.string,
                    symbol: ChatAppearance.Symbol.attach
                )
            }
            .padding(self.appearance.spacing.units(3))
            .background(self.appearance.theme.botSurface)
            .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(Self.accessibilityLabel)
        .accessibilityHint(Self.accessibilityHint)
    }
}

// MARK: - Accessibility contract

extension ImageUploadPromptView {

    /// VoiceOver label: the prompt line — the button title is the action spoken via the hint.
    static var accessibilityLabel: String {
        L10n.imageUploadPrompt.string
    }

    /// VoiceOver hint: what activating the card does.
    static var accessibilityHint: String {
        L10n.imageUploadHint.string
    }
}
