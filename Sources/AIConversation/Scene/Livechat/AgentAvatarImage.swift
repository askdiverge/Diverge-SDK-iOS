//
//  AgentAvatarImage.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Fronts an agent's message with that agent's photo, so the visitor can tell a person's replies
/// from the assistant's. A person glyph stands in while the photo loads, when it fails to load and
/// when the agent has none. VoiceOver reads the agent's name, or the generic word for an agent when
/// the message names no one.
struct AgentAvatarImage: ViewModifier {

    @Environment(\.appearance) private var appearance

    let agent: LivechatAgent?

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: self.appearance.spacing.units(2)) {
            self.avatar
            content
        }
    }

    private var avatar: some View {
        let badge = self.appearance.spacing.units(8)
        return Group {
            if let url = self.agent?.avatarUrl {
                RemoteImageView(url: url) { result in
                    switch result {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        self.glyph(badge: badge)
                    }
                } placeholder: {
                    self.glyph(badge: badge)
                }
            } else {
                self.glyph(badge: badge)
            }
        }
        .frame(width: badge, height: badge)
        .background(self.appearance.theme.botSurface)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(self.appearance.theme.botSurfaceBorder ?? .clear, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: self.agent))
        .accessibilityAddTraits(.isImage)
    }

    private func glyph(badge: CGFloat) -> some View {
        ChatAppearance.Symbol.agentAvatar
            .resizable()
            .scaledToFit()
            .frame(width: badge * 0.5, height: badge * 0.5)
            .foregroundStyle(self.appearance.theme.secondaryText)
    }
}

// MARK: - Accessibility contract

extension AgentAvatarImage {

    /// VoiceOver label: the agent's name, or the generic word for an agent when the message names
    /// no one.
    static func accessibilityLabel(for agent: LivechatAgent?) -> String {
        let name = agent?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.livechatAgentFallback.string : name
    }
}
