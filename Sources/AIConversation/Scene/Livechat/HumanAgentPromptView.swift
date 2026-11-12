//
//  HumanAgentPromptView.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Renders a `request_human_agent` marker as a card asking whether the visitor wants a person,
/// with a "Talk to a person" CTA and, while the card can still be answered, "No thanks". The
/// card hands over only while ``ChatView/ViewModel/canAcceptHumanAgentPrompt(inBotTurn:)`` holds,
/// and reads that in its own body so it updates while the conversation list stays put.
struct HumanAgentPromptView: View {

    @Environment(\.appearance) private var appearance

    let viewModel: ChatView.ViewModel
    let partId: String
    let turnID: UUID

    var body: some View {
        let isEnabled = self.viewModel.canAcceptHumanAgentPrompt(inBotTurn: self.turnID)
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            self.promptText
            HStack(spacing: self.appearance.spacing.units(4)) {
                self.acceptButton(isEnabled: isEnabled)
                if isEnabled {
                    self.declineButton
                }
            }
        }
        .padding(self.appearance.spacing.units(3))
        .background(self.appearance.theme.botSurface)
        .border(self.borderColor, width: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("livechat.humanAgentPrompt")
    }

    private func acceptButton(isEnabled: Bool) -> some View {
        Button {
            Task { await self.viewModel.acceptHumanAgentPrompt(partId: self.partId, inBotTurn: self.turnID) }
        } label: {
            AccentCapsuleLabel(
                title: L10n.livechatTalkToPerson.string,
                symbol: ChatAppearance.Symbol.person
            )
        }
        .buttonStyle(.plain)
        .minimumTouchTarget(alignment: .leading)
        .disabled(!isEnabled)
        .accessibilityLabel(L10n.livechatTalkToPerson.string)
        .accessibilityHint(isEnabled ? L10n.livechatHumanAgentHint.string : "")
        .accessibilityIdentifier("livechat.humanAgentAccept")
    }

    private var declineButton: some View {
        Button {
            self.viewModel.declineHumanAgentPrompt(partId: self.partId)
        } label: {
            Text(L10n.livechatNoThanks.string)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.secondaryText)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityLabel(L10n.livechatNoThanks.string)
        .accessibilityIdentifier("livechat.humanAgentDecline")
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
