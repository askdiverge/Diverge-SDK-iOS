//
//  ConversationSnapshot+GainedBotContent.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

extension ConversationSnapshot {

    /// Whether the newest bot turn is new or changed since `old` with no reply streaming in
    /// either: a livechat note, an agent's message or a system note arrived. While a reply
    /// streams the answer is `false`; the exchange the visitor's send started places that reply.
    func gainedBotContent(since old: ConversationSnapshot) -> Bool {
        guard self.streamingTurnID == nil, old.streamingTurnID == nil, let newest = self.incoming.last else {
            return false
        }
        return newest != old.incoming.last
    }
}
