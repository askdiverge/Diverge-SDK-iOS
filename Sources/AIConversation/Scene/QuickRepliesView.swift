//
//  QuickRepliesView.swift
//  AIConversation
//

import SwiftUI

/// Wrapping outlined capsule chips for in-conversation `quick_replies` parts.
/// Tap sends the label as the next user message via `onSelect`.
struct QuickRepliesView: View {

    let replies: [String]
    let onSelect: (String) -> Void

    var body: some View {
        OutlinedChipFlow(
            labels: self.replies,
            accessibilityPrefix: "quickReply",
            onSelect: self.onSelect
        )
    }
}
