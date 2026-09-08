//
//  AgentTypingIndicator.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Shows when the active livechat agent is typing.
struct AgentTypingIndicator: View {

    @Environment(\.appearance) private var appearance

    let agentName: String?

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            ProgressView()
                .controlSize(.mini)
            Text(self.copy)
                .font(self.appearance.font(size: 12))
                .foregroundStyle(self.appearance.theme.secondaryText)
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.vertical, self.appearance.spacing.units(1))
        .accessibilityIdentifier("livechat.agentTyping")
        .accessibilityLabel(self.copy)
    }

    private var copy: String {
        if let agentName, !agentName.isEmpty {
            return L10n.livechatAgentTypingNamed(agentName).string
        }
        return L10n.livechatAgentTyping.string
    }
}
