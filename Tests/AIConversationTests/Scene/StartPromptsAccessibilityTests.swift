//
//  StartPromptsAccessibilityTests.swift
//  AIConversationTests
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import Testing
@testable import AIConversation

@Suite("StartPromptsView — accessibility contract")
struct StartPromptsAccessibilityTests {

    @Test("hint is wired to a non-empty string resource")
    func hintWired() {
        #expect(!L10n.startPromptSendHint.string.isEmpty)
    }

    @Test("start-prompt copy exists in every locale")
    func catalogCoverage() throws {
        try StringCatalog.expectKeysInEveryLocale(["startPrompt.sendHint"])
    }
}
