//
//  FormField.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A dynamic form field definition carried inline on a form marker.
///
/// A missing `type` reads as `.text`, as the contract defines, and the deprecated `phone` alias
/// reads as `.tel`. A type this SDK has no control for decodes as `.unknown`.
/// [API ref](https://docs.askdiverge.ai/api#model/formfield)
package struct FormField: Decodable, Sendable, Equatable {

    /// The input control the client renders for the field, chosen per field by the operator who
    /// designs the form. The visitor's answer is submitted under the field's ``key``. A case is
    /// added when the backend introduces a new input type and the SDK ships a control for it.
    package enum FieldType: String, ExtendableEnum, Sendable, Equatable {
        case text
        case email
        case tel
        case textarea
        case file
        case dropdown
        case unknown
    }

    package let key: String
    package let label: String
    /// Hint text shown in the empty input. `nil` when the operator set none.
    package let placeholder: String?
    package let type: FieldType
    package let required: Bool
    package let options: [String]
    package let visibleWhen: [FormFieldCondition]

    package init(
        key: String,
        label: String,
        placeholder: String? = nil,
        type: FieldType = .text,
        required: Bool = false,
        options: [String] = [],
        visibleWhen: [FormFieldCondition] = []
    ) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.type = type
        self.required = required
        self.options = options
        self.visibleWhen = visibleWhen
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.label = try container.decode(String.self, forKey: .label)
        self.placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        self.type = try Self.decodeType(from: container)
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
        self.visibleWhen = try container.decodeIfPresent([FormFieldCondition].self, forKey: .visibleWhen) ?? []
    }

    /// Maps the wire string onto ``FieldType``: missing → `.text`, `phone` → `.tel`, and a value
    /// with no case → `.unknown`.
    private static func decodeType(from container: KeyedDecodingContainer<CodingKeys>) throws -> FieldType {
        guard let raw = try container.decodeIfPresent(String.self, forKey: .type) else {
            return .text
        }
        return raw == "phone" ? .tel : FieldType(rawValue: raw) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, placeholder, type, required, options, visibleWhen
    }
}
