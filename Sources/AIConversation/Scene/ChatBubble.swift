//
//  ChatBubble.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

/// A chat bubble's text.
private struct ChatBubble: View {

    @Environment(\.appearance) private var appearance

    let text: AttributedString

    var body: some View {
        Text(self.text)
            .font(self.appearance.font(size: 13))
            .padding(self.appearance.spacing.units(2))
    }
}

struct UserBubble: View {

    @Environment(\.appearance) private var appearance

    let text: AttributedString

    var body: some View {
        ChatBubble(text: self.text)
            .foregroundStyle(self.appearance.theme.userBubbleText)
            .background(self.appearance.theme.userBubble)
            .border(self.appearance.theme.userBubbleBorder ?? .clear, width: 1)
    }
}

struct BotBubble: View {

    @Environment(\.appearance) private var appearance

    let text: AttributedString

    var body: some View {
        ChatBubble(text: self.text)
            .foregroundStyle(self.appearance.theme.primaryText)
            .background(self.appearance.theme.botSurface)
            .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
    }
}
