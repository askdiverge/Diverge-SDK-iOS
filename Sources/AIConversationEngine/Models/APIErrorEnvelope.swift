//
//  APIErrorEnvelope.swift
//  AIConversationEngine
//

import Foundation

/// The body the Chatbot API returns with a non-2xx status before a stream starts —
/// `{ error: { message, params? } }`.
package struct APIErrorEnvelope: Decodable, Sendable {

    /// The `error` object of the envelope.
    package struct ErrorBody: Decodable, Sendable {
        /// Human-readable description of the failure.
        package let message: String
        /// The invalid values the API can point to. `nil` when the failure is not tied to
        /// specific fields.
        package let params: [ValidationError]?
    }

    /// The failure the request produced.
    package let error: ErrorBody
}
