//
//  OlderTurnsAnchorTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

@Suite("OlderTurnsAnchor — returning to the reader's place")
struct OlderTurnsAnchorTests {

    @Test("older turns landing above return the reader to the turn they were at")
    func landsOnTheTurnBelowTheNewOnes() {
        let (older, reader, newest) = (UUID(), UUID(), UUID())
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader)

        #expect(anchor.landing(from: [reader, newest], to: [older, reader, newest]) == reader)
        #expect(!anchor.isArmed)
    }

    @Test("an unarmed list stays where it is")
    func unarmedStays() {
        var anchor = OlderTurnsAnchor()

        #expect(anchor.landing(from: [UUID()], to: [UUID(), UUID()]) == nil)
    }

    @Test("a page that joined the first turn leaves the reader in place")
    func joinedTurnStays() {
        let (reader, newest) = (UUID(), UUID())
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader)

        #expect(anchor.landing(from: [reader], to: [reader, newest]) == nil)
        #expect(!anchor.isArmed)
    }

    @Test("a snapshot that changes no turns keeps it armed")
    func unchangedTurnsKeepItArmed() {
        let reader = UUID()
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader)

        #expect(anchor.landing(from: [reader], to: [reader]) == nil)
        #expect(anchor.isArmed)
    }

    @Test("a conversation replaced meanwhile lands nowhere")
    func replacedConversationLandsNowhere() {
        let reader = UUID()
        var anchor = OlderTurnsAnchor()
        anchor.arm(at: reader)

        #expect(anchor.landing(from: [reader], to: [UUID()]) == nil)
    }
}
