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
        /// HTTP 409 — an active livechat session owns the channel; re-route to livechat send.
        /// `popped` is the user text to re-send on the livechat path.
        case conflict(popped: String)
        /// HTTP 409 on `POST /livechat/messages` — the session is no longer active; re-route to AI.
        /// `popped` is the user text to re-send on `POST /messages`.
        case livechatInactive(popped: String)
        /// Recoverable — the user's text is popped back to the input for retry.
        /// `body` carries a server-supplied message when there is one; `nil` means the presenter
        /// substitutes generic copy.
        case retry(popped: String, body: String?)
        /// Another mutating operation (send/reset/delete) is already in flight.
        case busy(Reason)

        package enum Reason {
            case streaming, operation
        }
    }
}
