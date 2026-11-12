//
//  AgentAvatarAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Pins what VoiceOver reads for the avatar beside an agent's message. Under the `swift test` CLI
/// String Catalogs are not compiled and every key echoes itself, so copy is asserted by key
/// identity, never by English text.
///
/// `@MainActor` because the helper under test hangs off a SwiftUI modifier, which is main-actor
/// isolated.
@MainActor
@Suite("AgentAvatarImage — accessibility contract")
struct AgentAvatarAccessibilityTests {

    @Test("the label is the agent's name")
    func labelIsName() throws {
        let alice = try LivechatFixtures.agent("Alice")
        #expect(AgentAvatarImage.accessibilityLabel(for: alice) == "Alice")
    }

    @Test("an agent with a blank name reads as an agent")
    func blankNameFallsBack() throws {
        let unnamed = try LivechatFixtures.agent("  ")
        #expect(AgentAvatarImage.accessibilityLabel(for: unnamed) == L10n.livechatAgentFallback.string)
    }

    @Test("a message that names no agent reads as an agent")
    func noAgentFallsBack() {
        #expect(AgentAvatarImage.accessibilityLabel(for: nil) == L10n.livechatAgentFallback.string)
    }
}
