//
//  ConversationFormAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ConversationFormView — accessibility contract")
struct ConversationFormAccessibilityTests {

    @Test("contact form label is wired to a non-empty string resource")
    func contactLabel() {
        let form = ConversationForm.contact(ShowContactForm(partId: "p", fields: []))
        #expect(!ConversationFormView.accessibilityLabel(for: form).isEmpty)
        #expect(ConversationFormView.accessibilityLabel(for: form) == L10n.formContactTitle.string)
    }

    @Test("ticket form label is wired to a non-empty string resource")
    func ticketLabel() {
        let form = ConversationForm.supportTicket(ShowSupportTicket(partId: "p", fields: []))
        #expect(ConversationFormView.accessibilityLabel(for: form) == L10n.formTicketTitle.string)
    }

    @Test("custom form uses its display name as the label")
    func customLabel() {
        let form = ConversationForm.custom(ShowForm(
            partId: "p",
            formId: "f",
            name: "Sales lead",
            fields: []
        ))
        #expect(ConversationFormView.accessibilityLabel(for: form) == "Sales lead")
    }

    @Test("hint is wired to a non-empty string resource")
    func hint() {
        #expect(!ConversationFormView.accessibilityHint.isEmpty)
        #expect(ConversationFormView.accessibilityHint == L10n.formAccessibilityHint.string)
    }

    // `swift test` ships the raw catalog, so runtime lookups echo keys; the catalog JSON is the
    // contract we can check on every platform.

    @Test("field-level copy the controls speak exists in every locale: dropdown placeholder, required, read-only, done")
    func fieldLevelResources() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "form.selectOption", "form.required", "form.readOnly", "form.done",
        ])
    }

    @Test("min_filled_fields copy has plural variations (one ≠ other) in every locale")
    func minFilledPluralises() throws {
        let strings = try StringCatalog.strings()
        let localizations = try #require(strings["form.minFilled"]?["localizations"] as? [String: Any])
        #expect(Set(localizations.keys) == StringCatalog.locales)
        for (locale, value) in localizations {
            let plural = try #require(
                ((value as? [String: Any])?["variations"] as? [String: Any])?["plural"] as? [String: Any],
                "\(locale) has no plural variations"
            )
            #expect(plural["one"] != nil && plural["other"] != nil, "\(locale) lacks one/other")
            for (_, unit) in plural {
                let text = try #require(((unit as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String)
                #expect(text.contains("%lld"), "\(locale): every variation must keep the count placeholder")
            }
        }
    }
}
