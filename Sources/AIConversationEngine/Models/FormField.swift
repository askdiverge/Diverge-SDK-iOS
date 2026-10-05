//
//  FormField.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// A dynamic form field definition carried inline on a form marker.
///
/// Lenient on `type`: a missing or future value falls back to `.text` so a required field
/// never vanishes and makes the form unsubmittable. The deprecated `phone` alias maps to `.tel`.
/// [API ref](https://docs.askdiverge.ai/api#model/formfield)
package struct FormField: Decodable, Sendable, Equatable {

    /// The input control the client renders for the field, chosen per field by the operator who
    /// designs the form. The visitor's answer is submitted under the field's ``key``. A case is
    /// added when the backend introduces a new input type and the SDK ships a control for it.
    package enum FieldType: String, Sendable, Equatable {
        case text
        case email
        case tel
        case textarea
        case file
        case dropdown
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
        self.type = Self.decodeType(from: container)
        self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        self.options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
        self.visibleWhen = try container.decodeIfPresent([FormFieldCondition].self, forKey: .visibleWhen) ?? []
    }

    /// Maps the wire string onto ``FieldType``. Unknown / missing → `.text`; `phone` → `.tel`.
    private static func decodeType(from container: KeyedDecodingContainer<CodingKeys>) -> FieldType {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: .type) else {
            return .text
        }
        switch raw {
        case "text": return .text
        case "email": return .email
        case "tel", "phone": return .tel
        case "textarea": return .textarea
        case "file": return .file
        case "dropdown": return .dropdown
        default: return .text
        }
    }

    private enum CodingKeys: String, CodingKey {
        case key, label, placeholder, type, required, options, visibleWhen
    }
}
