//
//  ApiErrorEnvelope.swift
//  AIConversationCore
//

import Foundation

/// Standard API error body — `{ error: { code, message, params? } }`.
package struct ApiErrorEnvelope: Decodable, Sendable {

    package struct ErrorBody: Decodable, Sendable {
        package let code: String?
        package let message: String
        package let params: [ValidationError]?
    }

    package let error: ErrorBody
}

/// A single field-level validation failure from `error.params`.
package struct ValidationError: Decodable, Sendable, Equatable {
    package let field: String
    package let message: String

    package init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}
