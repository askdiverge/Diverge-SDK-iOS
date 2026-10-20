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
        /// Recoverable — the user's text is popped back to the input for retry.
        /// `body` carries a server-supplied message when there is one; `nil` means the presenter
        /// substitutes generic copy.
        case retry(popped: String, body: String?)
        /// The livechat session is no longer active (409 on a livechat send). The user's text is
        /// popped back so it can go to the assistant instead.
        case livechatInactive(popped: String)
        /// Another mutating operation (send/reset/delete) is already in flight.
        case busy(Reason)

        package enum Reason {
            case streaming, operation
        }
    }
}
