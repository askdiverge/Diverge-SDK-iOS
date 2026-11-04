//
//  ChatViewModelOpeningTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Opening the chat over a real ``ChatProvider``, with `/config` and history stubbed at the
/// `URLSession`. ``ScriptedURLProtocol`` intercepts before the network, so no server is involved.
@Suite("ChatView.ViewModel — opening")
@MainActor
struct ChatViewModelOpeningTests {

    @Test("a first history page that fails opens the chat on the greeting", arguments: [500, 401])
    func failedFirstPageOpensOnGreeting(status: Int) async throws {
        let viewModel = Self.makeSUT(history: .init(status: status))

        await viewModel.start()

        #expect(viewModel.phase == .ready)
        try await eventually { viewModel.snapshot?.turns.map(\.model) == [Self.greeting] }
    }
}

private extension ChatViewModelOpeningTests {

    static let greeting = ConversationSnapshot.Turn.bot([.text(AttributedString("Hi"))])

    /// A view model whose `/config` succeeds and whose every later request, history included,
    /// gets `history`. A failing `history` also fails the font fetch, which the chat opens without.
    static func makeSUT(history: ScriptedURLProtocol.Response) -> ChatView.ViewModel {
        let (service, _) = ChatServiceFixtures.makeSUT(responses: [.init(body: Data(Self.config.utf8)), history])
        return ChatView.ViewModel(
            service: service,
            contextProvider: nil,
            conversationFlow: .topDown,
            attachments: .disabled
        )
    }

    static let config = """
    {
      "display": {
        "name": "Bot",
        "avatar": { "url": null },
        "welcome_message": "Hi",
        "subtitle": null,
        "privacy_policy_url": "https://example.com/privacy"
      },
      "theme": {
        "brand": { "primary_color": "#000000" },
        "surface": { "background_color": "#FFFFFF", "muted_text_color": "#666666" },
        "header": {
          "alignment": "center",
          "logo": { "url": null },
          "button": { "background_color": "#EEEEEE", "icon_color": "#111111" }
        },
        "messages": {
          "assistant": {
            "background_color": "#F3F4F6",
            "text_color": "#111111",
            "thinking_border_gradient": ["#FFFFFF", "#000000"]
          },
          "user": { "background_color": "#4F46E5", "text_color": "#FFFFFF" }
        },
        "input": {
          "text_color": "#111111",
          "placeholder_color": "#999999",
          "send_button": {}
        },
        "product_card": { "discount_price_color": "#CC0000" },
        "font": {
          "ios": {
            "asset_url": "https://example.com/font.ttf",
            "sha256": "opening-tests-font",
            "format": "ttf"
          }
        }
      }
    }
    """
}
