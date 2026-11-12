//
//  LiveCards.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Remembers the form and "talk to a person" cards that arrived in a reply while the chat was
/// open, by `part_id`, so they stay fillable when the visitor closes the chat and opens it again.
/// A card restored from history that no presentation saw arrive stays read-only, as on the web
/// widget after a reload.
///
/// ``AIChat`` holds it, because each presentation builds a new view model. It lives in memory for
/// as long as its holder: one `AIChat`, or the shared configuration for instances minted from it.
@MainActor
final class LiveCards {

    private var partIDs: Set<String> = []

    /// Records the cards in `responses` as arrived live.
    func record(_ responses: [ChatResponse]) {
        self.partIDs.formUnion(responses.compactMap(Self.partID(of:)))
    }

    /// Whether any card in `responses` arrived live.
    func containsCard(in responses: [ChatResponse]) -> Bool {
        responses.contains { Self.partID(of: $0).map(self.partIDs.contains) ?? false }
    }

    /// Cleared when the conversation ends: on reset, data deletion and an expired session.
    func clear() {
        self.partIDs = []
    }

    private static func partID(of response: ChatResponse) -> String? {
        switch response {
        case .form(let form): form.partId
        case .requestHumanAgent(let prompt): prompt.partId
        default: nil
        }
    }
}
