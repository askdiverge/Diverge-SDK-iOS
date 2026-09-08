//
//  HumanAgentPromptView.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Renders a `request_human_agent` marker as a card with a single "Talk to a person" CTA.
struct HumanAgentPromptView: View {

    @Environment(\.appearance) private var appearance

    let onRequest: () -> Void

    var body: some View {
        Button(action: self.onRequest) {
            VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
                Text(L10n.livechatHumanAgentPrompt.string)
                    .font(self.appearance.font(size: 13))
                    .foregroundStyle(self.appearance.theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                AccentCapsuleLabel(
                    title: L10n.livechatTalkToPerson.string,
                    symbol: ChatAppearance.Symbol.person
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
        .accessibilityIdentifier("livechat.humanAgentPrompt")
    }
}

extension HumanAgentPromptView {

    static var accessibilityLabel: String {
        L10n.livechatHumanAgentPrompt.string
    }

    static var accessibilityHint: String {
        L10n.livechatHumanAgentHint.string
    }
}
