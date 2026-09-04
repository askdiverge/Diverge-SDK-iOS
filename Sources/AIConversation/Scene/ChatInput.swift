//
//  ChatInput.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-24.
//

import SwiftUI

/// The user input bar — a growing text field, a leading CTA, and the send button.
///
/// It owns the draft binding, layout, and styling. Send is enabled by the draft (non-blank)
struct ChatInput: View {

    @Binding var currentMessage: String

    @Environment(\.appearance) private var appearance

    let placeholder: String
    let leadingIcon: Image

    let onLeadingTap: () -> Void
    let onSend: () -> Void
    let inputFocus: FocusState<Bool>.Binding

    private var canSend: Bool {
        !self.currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var theme: ChatAppearance.Theme {
        self.appearance.theme
    }

    private var spacing: ChatAppearance.Spacing {
        self.appearance.spacing
    }

    var body: some View {
        VStack(spacing: 0) {
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
