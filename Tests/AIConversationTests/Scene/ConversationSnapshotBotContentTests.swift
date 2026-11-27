//
//  ConversationSnapshotBotContentTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ConversationSnapshot — bot content that arrives outside a streaming reply")
struct ConversationSnapshotBotContentTests {

    @Test("a livechat note on the newest bot turn is gained content")
    func noteOnNewestTurn() {
        let turn = Identified<[ChatResponse]>(model: [.text(AttributedString("I will connect you."))])
        let noted = Identified(id: turn.id, model: turn.model + [.livechatNote(LivechatNote(kind: .queued))])

        #expect(Self.makeSUT(incoming: [noted]).gainedBotContent(since: Self.makeSUT(incoming: [turn])))
    }

    @Test("an agent's message that starts a bot turn is gained content")
    func newBotTurn() {
        let first = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])
        let agent = Identified<[ChatResponse]>(model: [.agentText(AttributedString("Hi, Sam here"), agent: nil)])

        #expect(Self.makeSUT(incoming: [first, agent]).gainedBotContent(since: Self.makeSUT(incoming: [first])))
    }

    @Test("an unchanged newest bot turn is nothing gained, whatever the visitor adds")
    func unchangedBotTurn() {
        let reply = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])
        let question = Identified<[UserContent]>(model: [.text(AttributedString("hi"))])

        let old = Self.makeSUT(incoming: [reply])
        let new = Self.makeSUT(user: [question], incoming: [reply])

        #expect(!new.gainedBotContent(since: old))
    }

    @Test("an update of a streaming reply is nothing gained, and neither is the update that ends it")
    func streamingReply() {
        let partial = Identified<[ChatResponse]>(model: [.text(AttributedString("Hel"))])
        let grown = Identified(id: partial.id, model: [ChatResponse.text(AttributedString("Hello"))])

        let streaming = Self.makeSUT(incoming: [partial], streamingTurnID: partial.id)
        let stillStreaming = Self.makeSUT(incoming: [grown], streamingTurnID: partial.id)
        let ended = Self.makeSUT(incoming: [grown], streamingTurnID: nil)

        #expect(!stillStreaming.gainedBotContent(since: streaming))
        #expect(!ended.gainedBotContent(since: streaming))
    }

    @Test("a reply that starts streaming is nothing gained")
    func streamStarts() {
        let reply = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])
        let placeholder = Identified<[ChatResponse]>(model: [.placeholder(AttributedString("Thinking"))])

        let old = Self.makeSUT(incoming: [reply])
        let new = Self.makeSUT(incoming: [reply, placeholder], streamingTurnID: placeholder.id)

        #expect(!new.gainedBotContent(since: old))
    }

    @Test("a conversation replaced by a new one, such as after a reset, is gained content")
    func replacedConversation() {
        let reply = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])
        let welcome = Identified<[ChatResponse]>(model: [.text(AttributedString("Hi, how can I help?"))])

        #expect(Self.makeSUT(incoming: [welcome]).gainedBotContent(since: Self.makeSUT(incoming: [reply])))
    }

    @Test("earlier turns landing above an unchanged newest bot turn are nothing gained")
    func earlierTurnsAbove() {
        let newest = Identified<[ChatResponse]>(model: [.text(AttributedString("hello"))])
        let earlier = Identified<[ChatResponse]>(model: [.text(AttributedString("from last week"))])

        #expect(!Self.makeSUT(incoming: [earlier, newest]).gainedBotContent(since: Self.makeSUT(incoming: [newest])))
    }

    @Test("a conversation with no bot turn has gained nothing")
    func noBotTurn() {
        let question = Identified<[UserContent]>(model: [.text(AttributedString("hi"))])

        #expect(!Self.makeSUT(user: [question]).gainedBotContent(since: Self.makeSUT()))
    }
}

private extension ConversationSnapshotBotContentTests {

    static func makeSUT(
        user: [Identified<[UserContent]>] = [],
        incoming: [Identified<[ChatResponse]>] = [],
        streamingTurnID: UUID? = nil
    ) -> ConversationSnapshot {
        ConversationSnapshot(
            user: user,
            incoming: incoming,
            isUserInitiatedConversation: true,
            streamingTurnID: streamingTurnID,
            liveTurnIDs: [],
            canLoadOlder: false
        )
    }
}
