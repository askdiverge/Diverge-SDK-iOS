//
//  LivechatAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

/// Pins the VoiceOver / catalog contract for livechat copy.
@Suite("Livechat — accessibility / catalog")
struct LivechatAccessibilityTests {

    @Test("talk-to-person label is wired to a non-empty string resource")
    func talkToPersonWired() {
        #expect(!HumanAgentPromptView.accessibilityLabel.isEmpty)
        #expect(!HumanAgentPromptView.accessibilityHint.isEmpty)
        #expect(HumanAgentPromptView.accessibilityLabel != HumanAgentPromptView.accessibilityHint)
    }

    @Test("livechat catalog keys exist in every locale")
    func catalogKeysInEveryLocale() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "livechat.talkToPerson",
            "livechat.humanAgentPrompt",
            "livechat.humanAgentHint",
            "livechat.offline",
            "livechat.queuedNote",
            "livechat.endedNote",
            "livechat.leaveConfirmTitle",
            "livechat.leaveConfirmMessage",
            "livechat.leaveConfirmAction",
            "livechat.waitingPlaceholder",
            "livechat.agentTyping",
            "livechat.agentTypingNamed",
            "livechat.toolbarRequest",
            "livechat.toolbarLeave",
            "livechat.agentPlaceholder",
            "livechat.agentJoinedNote",
            "livechat.agentFallback",
            "livechat.a11yAvailable",
            "livechat.a11yOffline",
            "livechat.attachmentsDropped",
        ])
    }
}
