//
//  HumanAgentPromptView.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Renders a `request_human_agent` marker as a card with a single "Talk to a person" CTA. The
/// card hands over only while ``ChatView/ViewModel/canAcceptHumanAgentPrompt(inBotTurn:)`` holds,
/// and reads that in its own body so it updates while the conversation list stays put.
struct HumanAgentPromptView: View {

    @Environment(\.appearance) private var appearance

    let viewModel: ChatView.ViewModel
    let partId: String
    let turnID: UUID

    var body: some View {
        let isEnabled = self.viewModel.canAcceptHumanAgentPrompt(inBotTurn: self.turnID)
        Button {
            Task { await self.viewModel.acceptHumanAgentPrompt(partId: self.partId, inBotTurn: self.turnID) }
        } label: {
            self.card
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .minimumTouchTarget(alignment: .leading)
        .disabled(!isEnabled)
        .accessibilityLabel(L10n.livechatHumanAgentPrompt.string)
        .accessibilityHint(isEnabled ? L10n.livechatHumanAgentHint.string : "")
        .accessibilityIdentifier("livechat.humanAgentPrompt")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            self.promptText
            AccentCapsuleLabel(
                title: L10n.livechatTalkToPerson.string,
                symbol: ChatAppearance.Symbol.person
            )
        }
        .padding(self.appearance.spacing.units(3))
        .background(self.appearance.theme.botSurface)
        .border(self.borderColor, width: 1)
    }

    private var promptText: some View {
        Text(L10n.livechatHumanAgentPrompt.string)
            .font(self.appearance.font(size: 13))
            .foregroundStyle(self.appearance.theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var borderColor: Color {
        self.appearance.theme.botSurfaceBorder ?? .clear
    }
}
