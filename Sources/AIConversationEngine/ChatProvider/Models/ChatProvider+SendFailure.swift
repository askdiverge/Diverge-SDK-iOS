//
//  ChatProvider+SendFailure.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

extension ChatProvider {
    /// Failure surfaced from `send` for the VM to react to.
    package enum SendFailure: Error, Sendable, Equatable {
        /// The session ended (401) — conversation cleared, the in-flight message discarded.
        case sessionExpired
        /// Recoverable — the user's message is popped back to the input for retry.
        /// `body` carries a server-supplied message when there is one; `nil` means the presenter
        /// substitutes generic copy.
        case retry(popped: Draft, body: String?)
        /// The livechat session is no longer active (409 on a livechat send). The user's message
        /// is popped back so it can go to the assistant instead.
        case livechatInactive(popped: Draft)
        /// The assistant send was rejected with 409, which an active livechat session causes. The
        /// user's message is popped back so it can go to the agent once the session's state
        /// confirms one.
        case livechatActive(popped: Draft)
        /// Another mutating operation (send/reset/delete) is already in flight.
        case busy(Reason)

        package enum Reason {
            case streaming, operation
        }

        /// The message a failed send popped from the conversation: its text and attachments, for
        /// the caller to restore or send elsewhere.
        package struct Draft: Sendable, Equatable {
            /// The text the visitor typed; empty for an attachment-only send.
            package let text: String
            /// The attachments sent with it, in order.
            package let attachments: [OutgoingAttachment]
        }
    }
}
