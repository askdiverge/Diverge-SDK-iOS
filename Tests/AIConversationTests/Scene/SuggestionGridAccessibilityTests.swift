//
//  SuggestionGridAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Pins the VoiceOver contract of a suggestion card: what is spoken as the label and hint.
/// The `.isButton` trait comes from wrapping the card in `Button`, which is structural.
@Suite("SuggestionGridView — accessibility contract")
@MainActor
struct SuggestionGridAccessibilityTests {

    @Test("label is the title alone when there is no description")
    func labelTitleOnly() {
        let card = self.card(title: "Outfit 2", description: nil)
        #expect(SuggestionGridView.accessibilityLabel(for: card) == "Outfit 2")
    }

    @Test("label is the title alone when the description is empty")
    func labelIgnoresEmptyDescription() {
        let card = self.card(title: "Outfit 2", description: "")
        #expect(SuggestionGridView.accessibilityLabel(for: card) == "Outfit 2")
    }

    @Test("label joins title and description with a sentence break")
    func labelTitleAndDescription() {
        let card = self.card(title: "Outfit 2", description: "See all products from this look.")
        #expect(
            SuggestionGridView.accessibilityLabel(for: card)
                == "Outfit 2. See all products from this look."
        )
    }

    /// Under `xcodebuild test` (CI) the catalog is compiled and this resolves to copy; under the
    /// `swift test` CLI String Catalogs are not compiled and every key echoes itself. Assert only
    /// what holds on both runners: the hint is wired to a non-empty resource.
    @Test("hint is wired to a non-empty string resource")
    func hintIsWired() {
        #expect(!SuggestionGridView.accessibilityHint.isEmpty)
    }

    private func card(title: String, description: String?) -> Suggestions.Card {
        Suggestions.Card(
            id: "s1",
            title: title,
            description: description,
            imageUrl: URL(string: "https://cdn.example.com/s1.jpg"),
            promptText: "Show me outfit 2"
        )
    }
}
