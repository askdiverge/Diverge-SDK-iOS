//
//  ChatView+SessionEnded.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-07.
//

import Foundation

extension ChatView {
    /// Signals that a 401 ended the chat session. The conversation is already cleared.
    /// View presents  one-shot session-ended alert and  next send starts a fresh session.
    struct SessionEnded: Error {}
    struct DeletionFailed: Error {}
}
