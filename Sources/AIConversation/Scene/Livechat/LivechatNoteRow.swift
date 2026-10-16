//
//  LivechatNoteRow.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Centred, muted boundary line for livechat transitions.
struct LivechatNoteRow: View {

    let note: LivechatNote

    var body: some View {
        NoteRow(text: AttributedString(self.copy), identifier: "livechat.note")
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
