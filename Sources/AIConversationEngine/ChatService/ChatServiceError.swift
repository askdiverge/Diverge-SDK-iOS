//
//  ChatServiceError.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-08.
//

import Foundation
import AIConversationCore

/// Error  crossing upward out of the `ChatServicing`.
///
/// Lower-layer errors (`NetworkError`, the stream `Failure` payload, host hook
/// failures) are translated to these cases at the facade boundary — consumers
/// switch on facade semantics, never on transport internals.
package enum ChatServiceError: Error {

    /// A 401 — the session is dead. The caller resets local state.
    /// Next action re-authenticates.
    case sessionExpired

    /// The server terminated the message stream.
    /// Carries the wire payload — `code`, `message`, `retryable`.
    case stream(StreamEvent.Failure)

    /// The internal networking call to the chat API failed (transport, non-401 HTTP, decoding)
    case transport(NetworkError)

    /// A host hook (token / reset / delete) threw
    case provider(any Error)
}

extension ChatServiceError {

    /// Translates a lower-layer error into facade vocabulary.
    package init(_ error: any Error) {
        self = switch error {
        case let error as ChatServiceError: error
        case NetworkError.http(.unauthorized): .sessionExpired
        case let error as NetworkError: .transport(error)
        default: .provider(error)
        }
    }
}
