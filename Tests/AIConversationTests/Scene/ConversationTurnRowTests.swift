//
//  ConversationTurnRowTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Pins when the top-flowing list builds a turn's views again. The list lays out every turn of
/// the conversation and passes new closures on each update of a streaming reply, so this
/// comparison is what keeps the views of the turns that did not change.
///
/// `@MainActor` because the view under test is main-actor isolated.
@MainActor
@Suite("ConversationTurnRow — when a turn is built again")
struct ConversationTurnRowTests {

    @Test("a turn with the same content and role is the same row under new closures")
    func sameTurnIsSameRow() {
        let turn = Self.botTurn("Hello")
        var heights: [CGFloat] = []

        let first = Self.makeSUT(turn)
        let second = Self.makeSUT(turn, onHeightChange: { heights.append($0) })

        #expect(first == second)
    }

    @Test("a turn whose content changed under the same id is another row")
    func changedContentIsAnotherRow() {
        let turn = Self.botTurn("Hel")
        let grown = Identified(id: turn.id, model: ConversationSnapshot.Turn.bot([.text(AttributedString("Hello"))]))

        #expect(Self.makeSUT(turn) != Self.makeSUT(grown))
    }

    @Test("a turn that starts or stops streaming is another row")
    func streamingChangeIsAnotherRow() {
        let turn = Self.botTurn("Hello")

        #expect(Self.makeSUT(turn, isStreaming: true) != Self.makeSUT(turn, isStreaming: false))
    }

    @Test("a turn that stops being the newest bot turn is another row")
    func newestBotTurnChangeIsAnotherRow() {
        let turn = Self.botTurn("Hello")

        #expect(Self.makeSUT(turn, isNewestBotTurn: true) != Self.makeSUT(turn, isNewestBotTurn: false))
    }

    @Test("every stored input is compared, or is a closure the row keeps")
    func storedInputsAreAccountedFor() {
        let compared = ["turn", "isStreaming", "isNewestBotTurn"]
        let kept = ["content", "onHeightChange"]

        let stored = Mirror(reflecting: Self.makeSUT(Self.botTurn("Hello"))).children.compactMap(\.label)

        // An input added to the row belongs in `==`, unless a row that compares equal can keep
        // the value it was built with.
        #expect(stored.sorted() == (compared + kept).sorted())
    }
}

private extension ConversationTurnRowTests {

    static func botTurn(_ text: String) -> Identified<ConversationSnapshot.Turn> {
        Identified(model: .bot([.text(AttributedString(text))]))
    }

    static func makeSUT(
        _ turn: Identified<ConversationSnapshot.Turn>,
        isStreaming: Bool = false,
        isNewestBotTurn: Bool = true,
        onHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) -> ConversationTurnRow<EmptyView> {
        ConversationTurnRow(
            turn: turn,
            isStreaming: isStreaming,
            isNewestBotTurn: isNewestBotTurn,
            content: { _ in EmptyView() },
            onHeightChange: onHeightChange
        )
    }
}
