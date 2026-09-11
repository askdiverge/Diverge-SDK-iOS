//
//  ConversationSnapshotTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-09-05.
//

import Foundation
import Testing
@testable import AIConversationEngine

/// The two role-end helpers the top-flowing layout keys its exchange off. They must pick the
/// newest turn of each role regardless of how the roles are interleaved.
@Suite("ConversationSnapshot — role-end helpers")
struct ConversationSnapshotTests {

    @Test("two bot turns after the user turn — the last bot turn is the newest one")
    func userThenTwoBots() {
        let turns = [Self.user("u0"), Self.bot("b1"), Self.bot("b2")]
        let snapshot = Self.snapshot(turns)

        #expect(snapshot.lastUserTurnID == turns[0].id)
        #expect(snapshot.lastBotTurnID == turns[2].id)
    }

    @Test("two user turns after the bot turn — the last user turn is the newest one")
    func botThenTwoUsers() {
        let turns = [Self.bot("b0"), Self.user("u1"), Self.user("u2")]
        let snapshot = Self.snapshot(turns)

        #expect(snapshot.lastBotTurnID == turns[0].id)
        #expect(snapshot.lastUserTurnID == turns[2].id)
    }

    @Test("a single-role conversation reports nil for the missing role")
    func singleRole() {
        let bots = [Self.bot("b0"), Self.bot("b1")]
        #expect(Self.snapshot(bots).lastUserTurnID == nil)
        #expect(Self.snapshot(bots).lastBotTurnID == bots[1].id)

        let users = [Self.user("u0")]
        #expect(Self.snapshot(users).lastBotTurnID == nil)
        #expect(Self.snapshot(users).lastUserTurnID == users[0].id)
    }

    @Test("an empty conversation reports nil for both")
    func empty() {
        let snapshot = Self.snapshot([])
        #expect(snapshot.lastUserTurnID == nil)
        #expect(snapshot.lastBotTurnID == nil)
    }

    @Test("system turns are excluded from lastBotTurnID")
    func systemExcludedFromLastBot() {
        let turns = [
            Self.bot("b0"),
            Self.system("sys"),
            Self.user("u0")
        ]
        let snapshot = Self.snapshot(turns)
        #expect(snapshot.lastBotTurnID == turns[0].id)
        #expect(snapshot.lastUserTurnID == turns[2].id)
    }
}

private extension ConversationSnapshotTests {

    static func user(_ text: String) -> Identified<ConversationSnapshot.Turn> {
        Identified(model: .user([.text(AttributedString(text))]))
    }

    static func bot(_ text: String) -> Identified<ConversationSnapshot.Turn> {
        Identified(model: .bot([.text(AttributedString(text))]))
    }

    static func system(_ text: String) -> Identified<ConversationSnapshot.Turn> {
        Identified(model: .system([.text(AttributedString(text))]))
    }

    static func snapshot(_ turns: [Identified<ConversationSnapshot.Turn>]) -> ConversationSnapshot {
        ConversationSnapshot(turns: turns, streamingTurnID: nil, canLoadOlder: true)
    }
}
