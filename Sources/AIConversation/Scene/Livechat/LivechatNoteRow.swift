//
//  LivechatNoteRow.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Centred, muted boundary line for livechat transitions.
struct LivechatNoteRow: View {

    @Environment(\.appearance) private var appearance

    let note: LivechatNote

    var body: some View {
        Text(self.copy)
            .font(self.appearance.font(size: 12))
            .foregroundStyle(self.appearance.theme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, self.appearance.spacing.units(2))
            .accessibilityIdentifier("livechat.note")
    }

    private var copy: String {
        switch self.note.kind {
        case .queued:
            return L10n.livechatQueuedNote.string
        case .agentJoined(let name):
            return L10n.livechatAgentJoinedNote(name).string
        case .ended:
            return L10n.livechatEndedNote.string
        }
    }
}
