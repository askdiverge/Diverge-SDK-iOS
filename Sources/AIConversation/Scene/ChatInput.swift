//
//  ChatInput.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-24.
//

import SwiftUI

/// The user input bar — pending attachment chips, a growing text field, privacy + attach
/// controls, and the send button.
///
/// It owns the draft binding, layout, and styling. Send is enabled by non-blank text **or**
/// a non-empty attachment list. The attach control is present only when the host enabled
/// ``AIChat/Attachments/photoLibrary`` and is disabled while a photo encodes or a reply streams.
/// The photo picker itself lives on ``ChatView`` so the in-conversation upload prompt can
/// open the same picker.
struct ChatInput: View {

    @Binding var currentMessage: String
    @Binding var pendingAttachments: [PendingAttachment]

    @Environment(\.appearance) private var appearance

    let placeholder: String
    let leadingIcon: Image
    /// Whether the host offers photo attachments at all (`AIChat.Attachments.photoLibrary`).
    let showsAttachButton: Bool
    /// The shared enable rule for adding a photo — see `ChatView.ViewModel.canAttach`.
    let canAttach: Bool
    /// Swaps the attach glyph for a spinner and blocks send while a pick is being prepared.
    let isEncodingAttachment: Bool

    let onLeadingTap: () -> Void
    let onAttach: () -> Void
    let onSend: () -> Void
    let inputFocus: FocusState<Bool>.Binding

    private var canSend: Bool {
        let hasText = !self.currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !self.pendingAttachments.isEmpty) && !self.isEncodingAttachment
    }

    private var theme: ChatAppearance.Theme {
        self.appearance.theme
    }

    private var spacing: ChatAppearance.Spacing {
        self.appearance.spacing
    }

    var body: some View {
        VStack(spacing: 0) {
            if !self.pendingAttachments.isEmpty {
                PendingAttachmentStrip(
                    attachments: self.pendingAttachments,
                    onRemove: { id in
                        self.pendingAttachments.removeAll { $0.id == id }
                    }
                )
            }
            inputTextField
                .padding(.horizontal, self.spacing.units(4))
            buttonStack
                .padding(.horizontal, self.spacing.units(2))
        }
        .background(self.theme.inputBackground ?? self.theme.background)
        .padding(.top, self.spacing.units(3))
        .border(self.theme.inputBorder ?? .clear, width: 1)
    }

    private var inputTextField: some View {
        TextField(self.placeholder, text: self.$currentMessage, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...6)
            .focused(self.inputFocus)
            .font(self.appearance.font(size: 15))
            .foregroundStyle(self.theme.inputText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonStack: some View {
        HStack(spacing: self.spacing.units(3)) {
            self.leadingButton
            if self.showsAttachButton {
                self.attachButton
            }
            Spacer(minLength: 0)
            self.sendButton
        }
    }

    private var leadingButton: some View {
        Button(action: self.onLeadingTap) {
            self.leadingIcon
                .font(.system(size: 24))
                .foregroundStyle(self.theme.inputText)
                .padding(self.spacing.units(2))
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.privacyTitle.string)
        .accessibilityIdentifier("privacy.open")
    }

    /// Opens the shared photo picker on ``ChatView``. Disabled by the shared `canAttach` rule
    /// (encoding or streaming); the encoding spinner replaces the glyph while a pick is prepared.
    private var attachButton: some View {
        Button(action: self.onAttach) {
            if self.isEncodingAttachment {
                ProgressView()
                    .controlSize(.small)
            } else {
                ChatAppearance.Symbol.attach
                    .font(.system(size: 22))
            }
        }
        .foregroundStyle(self.theme.inputText)
        .padding(self.spacing.units(2))
        .minimumTouchTarget()
        .buttonStyle(.plain)
        .disabled(!self.canAttach)
        .accessibilityLabel(L10n.inputAttachPhoto.string)
    }

    private var sendButton: some View {
        Button(action: self.onSend) {
            ChatAppearance.Symbol.send
                .font(.system(size: 16))
                .foregroundStyle(self.theme.sendIcon ?? self.theme.accentForeground)
                .padding(self.spacing.units(2))
                .frame(minWidth: self.spacing.units(8), minHeight: self.spacing.units(8))
                .background(self.theme.accent, in: Circle())
                .padding(self.spacing.units(2))
                .minimumTouchTarget()
        }
        .buttonStyle(.plain)
        .opacity(self.canSend ? 1 : 0.5)
        .disabled(!self.canSend)
    }
}
