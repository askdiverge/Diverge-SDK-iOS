//
//  ConversationFormViewEqualityTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Pins when a form card's views are built again. A conversation passes each card new closures
/// on every update of a streaming reply, so this comparison is what keeps the views of a card
/// whose draft and rules did not change.
///
/// `@MainActor` because the view under test is main-actor isolated.
@MainActor
@Suite("ConversationFormView — when a card is built again")
struct ConversationFormViewEqualityTests {

    @Test("a card showing the same draft under the same rules is the same card under new closures")
    func sameDraftIsSameCard() {
        let model = FormSubmissionModel(form: Self.contact)
        var submits = 0

        let first = Self.makeSUT(model)
        let second = Self.makeSUT(model, onSubmit: { submits += 1 })

        #expect(first == second)
    }

    @Test("a card whose draft changed is another card")
    func changedDraftIsAnotherCard() {
        let model = FormSubmissionModel(form: Self.contact)
        var typed = model
        typed.setValue("Ada", for: "name")

        #expect(Self.makeSUT(model) != Self.makeSUT(typed))
    }

    @Test("a card that turns read-only, busy or loses photo attach is another card")
    func changedRulesAreAnotherCard() {
        let model = FormSubmissionModel(form: Self.contact)
        let card = Self.makeSUT(model)

        #expect(card != Self.makeSUT(model, isEditable: false))
        #expect(card != Self.makeSUT(model, isBusy: true))
        #expect(card != Self.makeSUT(model, offersAttachments: false))
    }

    @Test("every stored input is compared, or is one the card keeps")
    func storedInputsAreAccountedFor() {
        let compared = ["model", "isEditable", "offersAttachments", "isBusy"]
        let kept = [
            "_appearance", "focus", "onChange", "onSubmit", "onReload", "onPickFile", "onRemoveFile",
            "onPickTicketAttachment", "onRemoveTicketAttachment"
        ]

        let card = Self.makeSUT(FormSubmissionModel(form: Self.contact))
        let stored = Mirror(reflecting: card).children.compactMap(\.label)

        // An input added to the card belongs in `==`, unless a card that compares equal can keep
        // the value it was built with.
        #expect(stored.sorted() == (compared + kept).sorted())
    }
}

private extension ConversationFormViewEqualityTests {

    static let contact = ConversationForm.contact(ShowContactForm(
        partId: "part_contact_1",
        fields: [.init(key: "name", label: "Name", type: .text, required: true)]
    ))

    static func makeSUT(
        _ model: FormSubmissionModel,
        isEditable: Bool = true,
        offersAttachments: Bool = true,
        isBusy: Bool = false,
        onSubmit: @escaping () -> Void = {}
    ) -> ConversationFormView {
        ConversationFormView(
            model: model,
            isEditable: isEditable,
            offersAttachments: offersAttachments,
            isBusy: isBusy,
            focus: FocusState<String?>().projectedValue,
            onChange: { _, _ in },
            onSubmit: onSubmit,
            onReload: {},
            onPickFile: { _ in },
            onRemoveFile: { _ in },
            onPickTicketAttachment: {},
            onRemoveTicketAttachment: {}
        )
    }
}
