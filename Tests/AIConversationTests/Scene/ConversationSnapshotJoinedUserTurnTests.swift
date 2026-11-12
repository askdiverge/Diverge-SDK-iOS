//
//  ConversationSnapshotJoinedUserTurnTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ConversationSnapshot — a send that joins the newest visitor turn")
struct ConversationSnapshotJoinedUserTurnTests {

    @Test("a bubble on the newest visitor turn names that turn")
    func bubbleOnNewestTurn() {
        let turn = Identified<[UserContent]>(model: [Self.bubble("tack")])
        let joined = Identified(id: turn.id, model: turn.model + [Self.bubble("one more thing")])

        #expect(Self.snapshot(user: [joined]).joinedUserTurnID(since: Self.snapshot(user: [turn])) == turn.id)
    }

    @Test("a new visitor turn is a send of its own, so it names nothing, however many bubbles it brings")
    func newTurn() {
        let first = Identified<[UserContent]>(model: [Self.bubble("hi")])
        let second = Identified<[UserContent]>(model: [Self.bubble("thanks"), Self.bubble("and a photo")])

        #expect(Self.snapshot(user: [first, second]).joinedUserTurnID(since: Self.snapshot(user: [first])) == nil)
    }

    @Test("a bubble popped off the newest visitor turn names nothing")
    func poppedBubble() {
        let turn = Identified<[UserContent]>(model: [Self.bubble("tack"), Self.bubble("retry me")])
        let popped = Identified(id: turn.id, model: [Self.bubble("tack")])

        #expect(Self.snapshot(user: [popped]).joinedUserTurnID(since: Self.snapshot(user: [turn])) == nil)
    }

    @Test("a reply below the visitor turn names nothing")
    func replyBelow() {
        let turn = Identified<[UserContent]>(model: [Self.bubble("hi")])
        let reply = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])

        #expect(Self.snapshot(user: [turn], incoming: [reply]).joinedUserTurnID(since: Self.snapshot(user: [turn])) == nil)
    }
}

private extension ConversationSnapshotJoinedUserTurnTests {

    static func bubble(_ text: String) -> UserContent {
        .text(AttributedString(text))
    }

    static func snapshot(
        user: [Identified<[UserContent]>],
        incoming: [Identified<[ChatResponse]>] = []
    ) -> ConversationSnapshot {
        ConversationSnapshot(
            user: user,
            incoming: incoming,
            isUserInitiatedConversation: true,
            streamingTurnID: nil,
            liveTurnIDs: [],
            canLoadOlder: false
        )
    }
}
