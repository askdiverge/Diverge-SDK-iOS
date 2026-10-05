//
//  FormFieldDecodingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins how a form field and its visibility conditions decode from the shapes form markers carry
/// inline. A field that decodes differently from what the operator configured changes what the
/// visitor is asked to fill in.
@Suite("FormField — decoding against the API contract")
struct FormFieldDecodingTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("a field with only a key and label takes the contract defaults")
    func minimalFieldDefaults() throws {
        let field = try self.decodeField(#"{"key":"name","label":"Your name"}"#)

        #expect(field.key == "name")
        #expect(field.label == "Your name")
        #expect(field.placeholder == nil)
        #expect(field.type == .text)
        #expect(field.required == false)
        #expect(field.options.isEmpty)
        #expect(field.visibleWhen.isEmpty)
    }

    @Test("the deprecated phone type decodes as tel")
    func phoneAliasDecodesAsTel() throws {
        let field = try self.decodeField(#"{"key":"phone","label":"Phone","type":"phone"}"#)

        #expect(field.type == .tel)
    }

    @Test("an unrecognised type decodes as text")
    func unknownTypeDecodesAsText() throws {
        let field = try self.decodeField(#"{"key":"when","label":"When","type":"some_future_type"}"#)

        #expect(field.type == .text)
    }

    @Test("a dropdown decodes its options and visibility condition")
    func dropdownWithCondition() throws {
        let field = try self.decodeField("""
            {
              "key": "plan",
              "label": "Plan",
              "placeholder": "Pick a plan",
              "type": "dropdown",
              "required": true,
              "options": ["Basic", "Pro"],
              "visible_when": [{ "field": "topic", "operator": "equals", "value": "billing" }]
            }
            """)

        #expect(field.placeholder == "Pick a plan")
        #expect(field.type == .dropdown)
        #expect(field.required)
        #expect(field.options == ["Basic", "Pro"])
        let condition = try #require(field.visibleWhen.first)
        #expect(condition.field == "topic")
        #expect(condition.operator == .equals)
        #expect(condition.value == "billing")
    }

    @Test("a condition without an operator compares for equality")
    func conditionOperatorDefaultsToEquals() throws {
        let field = try self.decodeField("""
            {"key":"plan","label":"Plan","visible_when":[{"field":"topic","value":"billing"}]}
            """)

        #expect(field.visibleWhen.first?.operator == .equals)
    }

    @Test("an unrecognised condition operator decodes to .unknown")
    func unknownConditionOperator() throws {
        let field = try self.decodeField("""
            {"key":"plan","label":"Plan","visible_when":[{"field":"topic","operator":"some_future_operator","value":"billing"}]}
            """)

        #expect(field.visibleWhen.first?.operator == .unknown)
    }

    @Test("a malformed condition fails the field")
    func malformedConditionThrows() {
        #expect(throws: DecodingError.self) {
            try self.decodeField(#"{"key":"plan","label":"Plan","visible_when":[{"field":"topic"}]}"#)
        }
    }

    @Test("a field without a label fails to decode")
    func missingLabelThrows() {
        #expect(throws: DecodingError.self) {
            try self.decodeField(#"{"key":"email","label":null}"#)
        }
    }

    // MARK: - Fixtures

    private func decodeField(_ json: String) throws -> FormField {
        try self.decoder.decode(FormField.self, from: Data(json.utf8))
    }
}
