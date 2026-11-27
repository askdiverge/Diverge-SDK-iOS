//
//  NewestTurnRestTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

/// Pins when the top-flowing list scrolls arriving bot content into view: while it rests on its
/// newest turn and nothing else places it.
///
/// `@MainActor` because the type under test is main-actor isolated.
@MainActor
@Suite("NewestTurnRest — following content that arrives at the newest turn")
struct NewestTurnRestTests {

    @Test("a list that just opened follows")
    func opensResting() {
        let sut = Self.makeSUT()

        #expect(Self.follows(sut))
    }

    @Test("a reader who dragged the list is left where they are, until a scroll ends on the newest turn")
    func readerScroll() {
        let sut = Self.makeSUT()

        sut.readerScrolled()
        #expect(!Self.follows(sut))

        sut.scrollEnded(onNewestTurn: false)
        #expect(!Self.follows(sut))

        sut.scrollEnded(onNewestTurn: true)
        #expect(Self.follows(sut))
    }

    @Test("a scroll that ends away from the newest turn stops the following, drag or not")
    func scrollEndsAway() {
        let sut = Self.makeSUT()

        sut.scrollEnded(onNewestTurn: false)

        #expect(!Self.follows(sut))
    }

    @Test("asking for earlier turns stops the following")
    func earlierTurns() {
        let sut = Self.makeSUT()

        sut.askedForEarlierTurns()

        #expect(!Self.follows(sut))
    }

    @Test("a reply that grew with no exchange holding it leaves the reader in it; a held one changes nothing")
    func replyGrowth() {
        let held = Self.makeSUT()
        held.replyGrew(heldByExchange: true)
        #expect(Self.follows(held))

        let released = Self.makeSUT()
        released.replyGrew(heldByExchange: false)
        #expect(!Self.follows(released))
    }

    @Test("an exchange that holds its user turn at the top places the list itself")
    func heldExchange() {
        let sut = Self.makeSUT()

        #expect(!sut.follows(holdsExchange: true, bufferRemains: false, isEditingForm: false))
    }

    @Test("content that arrives while an exchange's buffer remains lands in the buffer, with no scroll")
    func remainingBuffer() {
        let sut = Self.makeSUT()

        #expect(!sut.follows(holdsExchange: false, bufferRemains: true, isEditingForm: false))
    }

    @Test("a reader in a form field keeps their place, and the following is back when they leave it")
    func formField() {
        let sut = Self.makeSUT()

        #expect(!sut.follows(holdsExchange: false, bufferRemains: false, isEditingForm: true))
        #expect(sut.follows(holdsExchange: false, bufferRemains: false, isEditingForm: false))
    }
}

private extension NewestTurnRestTests {

    static func makeSUT() -> NewestTurnRest {
        NewestTurnRest()
    }

    /// Whether `sut` follows with nothing else placing the list.
    static func follows(_ sut: NewestTurnRest) -> Bool {
        sut.follows(holdsExchange: false, bufferRemains: false, isEditingForm: false)
    }
}
