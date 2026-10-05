//
//  FormFieldCondition.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A condition evaluated against the visitor's answer to an earlier form field.
/// Only `equals` is supported today; reserved for future operators.
/// [API ref](https://docs.askdiverge.ai/api#model/formfieldcondition)
package struct FormFieldCondition: Decodable, Sendable, Equatable {

    /// How ``value`` is compared with the visitor's answer to ``field``, chosen by the operator
    /// who designs the form. The client evaluates the condition to decide whether the field is
    /// shown. A case is added when the backend supports a new comparison; unrecognised values
    /// decode to `.unknown`.
    package enum Operator: String, ExtendableEnum, Sendable {
        case equals
        case unknown
    }

    /// Key of a `dropdown` field defined earlier in the same `fields` array.
    package let field: String
    package let `operator`: Operator
    package let value: String

    package init(field: String, operator: Operator = .equals, value: String) {
        self.field = field
        self.operator = `operator`
        self.value = value
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.field = try container.decode(String.self, forKey: .field)
        self.value = try container.decode(String.self, forKey: .value)
        self.operator = try container.decodeIfPresent(Operator.self, forKey: .operator) ?? .equals
    }

    private enum CodingKeys: String, CodingKey {
        case field, `operator`, value
    }
}
