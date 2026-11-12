//
//  ConversationSnapshot+JoinedUserTurn.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

extension ConversationSnapshot {

    /// The newest visitor turn's id when that turn gained a bubble since `old`: the visitor sent
    /// again before their last message had a reply, such as a second message to an agent, so the
    /// send joined the turn instead of starting one. `nil` otherwise.
    func joinedUserTurnID(since old: ConversationSnapshot) -> UUID? {
        guard let newest = self.user.last, let previous = old.user.last,
              newest.id == previous.id, newest.model.count > previous.model.count else {
            return nil
        }
        return newest.id
    }
}
