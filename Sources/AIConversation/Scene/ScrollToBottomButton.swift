//
//  ScrollToBottomButton.swift
//  AIConversation
//

import SwiftUI

/// The jump-to-newest control every conversation list shares. It sits in the trailing corner, clear
/// of centred content such as a form's Submit label, and wears the thinking border while a reply
/// streams.
struct ScrollToBottomButton: View {

    @Environment(\.appearance) private var appearance

    let isVisible: Bool
    let isStreaming: Bool
    let action: () -> Void

    var body: some View {
        IconButton(icon: ChatAppearance.Symbol.scrollToBottom, action: self.action)
            .modifier(ThinkingBorderEffect(isActive: self.isStreaming, shape: Circle()))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .padding(.bottom, self.appearance.spacing.units(2))
            .padding(.trailing, self.appearance.spacing.units(4))
            .opacity(self.isVisible ? 1 : 0)
            .allowsHitTesting(self.isVisible)
            .animation(.easeInOut(duration: 0.2), value: self.isVisible)
    }
}
