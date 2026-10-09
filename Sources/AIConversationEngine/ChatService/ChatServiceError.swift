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

    /// A 409 — the request conflicts with server state. Each ``ChatServicing`` method that maps it
    /// says what it means there.
    case conflict

    /// The server terminated the message stream.
    /// Carries the wire payload — `code`, `message`, `retryable`.
    case stream(StreamEvent.Failure)

    /// The internal networking call to the chat API failed (transport, decoding, or an HTTP
    /// status the facade gives no meaning of its own).
    case transport(NetworkError)

    /// The API rejected the request body: a 422, or any status whose error envelope names
    /// invalid values. Carries the envelope's `message` and its `params`.
    case validation(message: String, params: [ValidationError])

    /// A host hook (token / reset / delete) threw
    case provider(any Error)
}

extension ChatServiceError {

    /// Translates a lower-layer error into facade vocabulary.
    package init(_ error: any Error) {
        self = switch error {
        case let error as ChatServiceError: error
        case NetworkError.http(.unauthorized): .sessionExpired
        case NetworkError.http(.unhandled(let status, let body)):
            Self.validation(status: status, body: body) ?? .transport(.http(.unhandled(status: status, body: body)))
        case let error as NetworkError: .transport(error)
        default: .provider(error)
        }
    }

    /// Whether the same request may succeed when tried again: the connection failed, the server
    /// timed out, limited the rate or failed with a 5xx, or a host hook threw.
    package var isTransient: Bool {
        switch self {
        case .transport(.http(.unhandled(let status, _))): status >= 500 || status == 408 || status == 429
        case .transport(.connection), .transport(.unknown), .provider: true
        default: false
        }
    }
}

private extension ChatServiceError {

    /// The rejected request's error envelope as ``validation(message:params:)``, or `nil` when
    /// the status and body carry no validation failure.
    static func validation(status: Int, body: Data) -> Self? {
        // A body in another shape (a proxy's HTML page, a legacy error string) maps by status alone.
        guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body) else { return nil }
        let params = envelope.error.params ?? []
        guard status == 422 || !params.isEmpty else { return nil }
        return .validation(message: envelope.error.message, params: params)
    }
}
