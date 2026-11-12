//
//  OlderTurnsAnchorTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("OlderTurnsAnchor — returning to the reader's place")
struct OlderTurnsAnchorTests {

    @Test("older turns landing above return the reader to the turn they were at")
    func landsOnTheTurnBelowTheNewOnes() {
        let (older, reader, newest) = (Self.turn("older"), Self.turn("reader"), Self.turn("newest"))
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader.id)

        #expect(anchor.landing(from: [reader, newest], to: [older, reader, newest]) == .landed(returnTo: reader.id))
        #expect(!anchor.isArmed)
    }

    @Test("an unarmed list stays where it is")
    func unarmedStays() {
        var anchor = OlderTurnsAnchor()

        #expect(anchor.landing(from: [Self.turn("a")], to: [Self.turn("b"), Self.turn("a")]) == .none)
    }

    @Test("a page that joined the first turn lands, and leaves the reader in place")
    func joinedTurnStays() {
        let (reader, newest) = (Self.turn("reader"), Self.turn("newest"))
        let joined = Identified(id: reader.id, model: ConversationSnapshot.Turn.bot([
            .text(AttributedString("older")),
            .text(AttributedString("reader"))
        ]))
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader.id)

        #expect(anchor.landing(from: [reader, newest], to: [joined, newest]) == .landed(returnTo: nil))
        #expect(!anchor.isArmed)
    }

    @Test("a reply or agent message below the first turn leaves it waiting for the page")
    func changeBelowKeepsItArmed() {
        let (older, reader, reply) = (Self.turn("older"), Self.turn("reader"), Self.turn("reply"))
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader.id)

        #expect(anchor.landing(from: [reader], to: [reader, reply]) == .none)
        #expect(anchor.isArmed)
        #expect(anchor.landing(from: [reader, reply], to: [older, reader, reply]) == .landed(returnTo: reader.id))
    }

    @Test("a snapshot that changes no turns keeps it armed")
    func unchangedTurnsKeepItArmed() {
        let reader = Self.turn("reader")
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader.id)

        #expect(anchor.landing(from: [reader], to: [reader]) == .none)
        #expect(anchor.isArmed)
    }

    @Test("a conversation replaced meanwhile lands nowhere")
    func replacedConversationLandsNowhere() {
        let reader = Self.turn("reader")
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader.id)

        #expect(anchor.landing(from: [reader], to: [Self.turn("other")]) == .landed(returnTo: nil))
    }
}

private extension OlderTurnsAnchorTests {

    /// A bot turn with one bubble of `text`.
    static func turn(_ text: String) -> Identified<ConversationSnapshot.Turn> {
        Identified(model: .bot([.text(AttributedString(text))]))
    }
}
