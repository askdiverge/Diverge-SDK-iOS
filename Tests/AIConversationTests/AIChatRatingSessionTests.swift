//
//  AIChatRatingSessionTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

@Suite("AIChat — rating session")
@MainActor
struct AIChatRatingSessionTests {

    @Test("instances from the shared configuration share the rated flag; a direct one keeps its own")
    func sharedConfigurationSharesRatedFlag() {
        let configuration = AIChat.Configuration(
            tokenProvider: { "token" },
            resetConversation: { "token" },
            deleteData: {}
        )
        AIChat.configure(configuration)

        let first = AIChat()
        let second = AIChat()
        let direct = AIChat(configuration)

        #expect(first.ratingSession === second.ratingSession)
        #expect(direct.ratingSession !== first.ratingSession)
    }

    @Test("a new shared configuration starts a new rated flag")
    func newConfigurationStartsOver() {
        let configuration = AIChat.Configuration(
            tokenProvider: { "token" },
            resetConversation: { "token" },
            deleteData: {}
        )
        AIChat.configure(configuration)
        let before = AIChat()

        AIChat.configure(configuration)

        #expect(AIChat().ratingSession !== before.ratingSession)
    }
}
