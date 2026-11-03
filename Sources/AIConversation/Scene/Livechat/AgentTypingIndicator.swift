//
//  AgentTypingIndicator.swift
//  AIConversation
//

import SwiftUI

/// Shows when the active livechat agent is typing, and tells VoiceOver when it appears. The
/// spinner is left out under Reduce Motion.
struct AgentTypingIndicator: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let agentName: String?

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            if !self.reduceMotion {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(self.copy)
                .font(self.appearance.font(size: 12))
                .foregroundStyle(self.appearance.theme.secondaryText)
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.vertical, self.appearance.spacing.units(1))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("livechat.agentTyping")
        .accessibilityLabel(self.copy)
        .onAppear { AccessibilityNotification.Announcement(self.copy).post() }
    }

    private var copy: String {
        if let agentName, !agentName.isEmpty {
            return L10n.livechatAgentTypingNamed(agentName).string
        }
        return L10n.livechatAgentTyping.string
    }
}
