//
//  ValidationError.swift
//  AIConversationEngine
//

import Foundation

/// A single field-level validation failure from `error.params`.
package struct ValidationError: Decodable, Sendable, Equatable {

    /// Path of the invalid value in the request body, as the API reports it
    /// (for example `message.parts.0.text`).
    package let field: String
    /// Human-readable description of what is wrong with the value.
    package let message: String

    /// Creates a failure for the value at `field`.
    package init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}
