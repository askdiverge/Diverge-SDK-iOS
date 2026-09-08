//
//  ChatViewModelProductCardTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — product card CTAs")
@MainActor
struct ChatViewModelProductCardTests {

    @Test("showsAddToCart is true only when config enables cart and the host supplied a callback")
    func showsAddToCartGate() {
        let withHook = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onAddToCart: { _ in }
        )
        withHook.setProductCardForTesting(openLabel: "Se produkt", addToCartEnabled: true)
        #expect(withHook.showsAddToCart == true)
        #expect(withHook.productOpenLabel == "Se produkt")

        let noHook = ChatView.ViewModel.forTesting(provider: StubChatProviding(), onAddToCart: nil)
        noHook.setProductCardForTesting(openLabel: nil, addToCartEnabled: true)
        #expect(noHook.showsAddToCart == false)

        let disabled = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onAddToCart: { _ in }
        )
        disabled.setProductCardForTesting(openLabel: "View", addToCartEnabled: false)
        #expect(disabled.showsAddToCart == false)
    }

    @Test("blank open labels become nil so the view can fall back to L10n")
    func blankOpenLabelNil() {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        viewModel.setProductCardForTesting(openLabel: "   ", addToCartEnabled: false)
        #expect(viewModel.productOpenLabel == nil)
    }
}
