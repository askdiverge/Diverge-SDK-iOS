//
//  PendingAttachmentStrip.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Horizontal strip of pending photo chips above the composer text field.
struct PendingAttachmentStrip: View {

    @Environment(\.appearance) private var appearance

    let attachments: [PendingAttachment]
    let onRemove: (PendingAttachment.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: self.appearance.spacing.units(2)) {
                ForEach(self.attachments) { pending in
                    self.chip(pending)
                }
            }
            .padding(.horizontal, self.appearance.spacing.units(4))
        }
        .padding(.bottom, self.appearance.spacing.units(2))
    }

    private func chip(_ pending: PendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            pending.thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipped()
                .background(self.appearance.theme.botSurface)
                .accessibilityHidden(true)

            // Small glyph, full-size hit area: the 44 pt target hangs off the chip's corner.
            Button {
                self.onRemove(pending.id)
            } label: {
                ChatAppearance.Symbol.close
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(self.appearance.theme.accentForeground)
                    .padding(4)
                    .background(self.appearance.theme.accent, in: Circle())
                    .minimumTouchTarget(alignment: .topTrailing)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .accessibilityLabel(L10n.attachmentRemove.string)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pending.displayName)
    }
}
