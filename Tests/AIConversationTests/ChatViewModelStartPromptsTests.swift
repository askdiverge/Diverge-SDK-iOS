//
//  ChatViewModelStartPromptsTests.swift
//  AIConversationTests
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — start prompts")
@MainActor
struct ChatViewModelStartPromptsTests {

    @Test("shouldShowStartPrompts is true for a welcome-only conversation with prompts")
    func welcomeOnlyShows() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.setStartPromptsForTesting([
            StartPrompt(promptText: "Track my order")
        ])
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))]))
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldShowStartPrompts == true)
    }

    @Test("shouldShowStartPrompts is false once a user turn exists")
    func userTurnHides() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.setStartPromptsForTesting([
            StartPrompt(promptText: "Track my order")
        ])
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))])),
            Identified(model: .user([.text("hello")])),
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldShowStartPrompts == false)
    }

    @Test("shouldShowStartPrompts is false when no prompts are configured")
    func emptyPromptsHide() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))]))
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldShowStartPrompts == false)
    }

    @Test("shouldShowStartPrompts is false while a reply is streaming")
    func streamingHides() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.setStartPromptsForTesting([
            StartPrompt(promptText: "Track my order")
        ])
        let streamingID = UUID()
        provider.publish(ConversationSnapshot(turns: [
            Identified(id: streamingID, model: .bot([.text(AttributedString("…"))]))
        ], streamingTurnID: streamingID, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)

        #expect(viewModel.shouldShowStartPrompts == false)
    }

    @Test("applyStartPromptsFromConfig matches page the same way bootstrap does")
    func bootstrapMatchingUsesPageContext() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.applyStartPromptsFromConfig(
            [
                StartPrompt(promptText: "Track my order"),
                StartPrompt(promptText: "Find a size", urlPattern: "/products"),
            ],
            page: "https://shop.example.com/products/123"
        )
        #expect(viewModel.startPrompts.map(\.promptText) == ["Find a size"])

        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))]))
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)
        #expect(viewModel.shouldShowStartPrompts == true)
    }

    @Test("reset restores shouldShowStartPrompts once welcome-only history returns")
    func resetRestoresChips() async {
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(provider: provider)
        viewModel.setStartPromptsForTesting([
            StartPrompt(promptText: "Track my order")
        ])
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))])),
            Identified(model: .user([.text("hello")])),
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitForSnapshot(viewModel)
        #expect(viewModel.shouldShowStartPrompts == false)

        await viewModel.reset()
        provider.publish(ConversationSnapshot(turns: [
            Identified(model: .bot([.text(AttributedString("Welcome"))]))
        ], streamingTurnID: nil, canLoadOlder: false))
        await Self.waitUntil(viewModel) { $0.snapshot?.lastUserTurnID == nil }

        #expect(viewModel.shouldShowStartPrompts == true)
    }

    private static func waitForSnapshot(_ viewModel: ChatView.ViewModel) async {
        await self.waitUntil(viewModel) { $0.snapshot != nil }
    }

    private static func waitUntil(
        _ viewModel: ChatView.ViewModel,
        _ predicate: (ChatView.ViewModel) -> Bool
    ) async {
        for _ in 0..<50 {
            if predicate(viewModel) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@Suite("StartPromptMatching")
struct StartPromptMatchingTests {

    private let global = StartPrompt(promptText: "Track my order", urlPattern: nil)
    private let products = StartPrompt(promptText: "Find a size", urlPattern: "/products")
    private let cart = StartPrompt(promptText: "Checkout help", urlPattern: "/cart")

    @Test("with no page context, only global (null-pattern) prompts remain")
    func noPageFallsBackToGlobals() {
        let selected = StartPromptMatching.select(
            [self.global, self.products, self.cart],
            page: nil
        )
        #expect(selected.map(\.promptText) == ["Track my order"])
    }

    @Test("an empty page string falls back to globals")
    func emptyPageFallsBackToGlobals() {
        let selected = StartPromptMatching.select(
            [self.global, self.products],
            page: ""
        )
        #expect(selected.map(\.promptText) == ["Track my order"])
    }

    @Test("a matching pattern suppresses globals")
    func patternBeatsGlobals() {
        let selected = StartPromptMatching.select(
            [self.global, self.products, self.cart],
            page: "https://shop.example.com/products/123"
        )
        #expect(selected.map(\.promptText) == ["Find a size"])
    }

    @Test("multiple matching patterns are all kept")
    func stackedPatterns() {
        let wide = StartPrompt(promptText: "Any product", urlPattern: "/p")
        let selected = StartPromptMatching.select(
            [self.global, wide, self.products],
            page: "https://shop.example.com/products/123"
        )
        #expect(selected.map(\.promptText) == ["Any product", "Find a size"])
    }

    @Test("no pattern match falls back to globals")
    func noMatchFallsBack() {
        let selected = StartPromptMatching.select(
            [self.global, self.products],
            page: "https://shop.example.com/about"
        )
        #expect(selected.map(\.promptText) == ["Track my order"])
    }

    @Test("a SKU blurb that does not contain the pattern falls back to globals")
    func skuBlurbDoesNotMatchPathPattern() {
        let selected = StartPromptMatching.select(
            [self.global, self.products],
            page: "PDP · Rieker Men's shoes 13510-00 black"
        )
        #expect(selected.map(\.promptText) == ["Track my order"])
    }

    @Test("blank prompt_text is dropped before matching")
    func blankPromptDropped() {
        let blank = StartPrompt(promptText: "   ", urlPattern: nil)
        let selected = StartPromptMatching.select(
            [blank, self.global],
            page: nil
        )
        #expect(selected.map(\.promptText) == ["Track my order"])
    }

    @Test("duplicate prompt_text rows both remain — identity is the chip index, not the text")
    func duplicateTextKept() {
        let twin = StartPrompt(promptText: "Track my order", urlPattern: nil)
        let selected = StartPromptMatching.select(
            [self.global, twin],
            page: nil
        )
        #expect(selected.count == 2)
        #expect(selected.map(\.promptText) == ["Track my order", "Track my order"])
    }
}
