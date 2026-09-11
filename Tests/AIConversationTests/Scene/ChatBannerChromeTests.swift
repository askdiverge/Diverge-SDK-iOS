//
//  ChatBannerChromeTests.swift
//  AIConversationTests
//

import SwiftUI
import Testing
@testable import AIConversation

@Suite("ChatBannerChrome hex fallback")
struct ChatBannerChromeTests {

    @Test("nil and unparseable fill use accent")
    func fillFallsBackToAccent() {
        let accent = Color.red
        #expect(ChatBannerChrome.fill(hex: nil, accent: accent) == accent)
        #expect(ChatBannerChrome.fill(hex: "not-a-color", accent: accent) == accent)
        #expect(ChatBannerChrome.fill(hex: "", accent: accent) == accent)
    }

    @Test("valid hex fill parses")
    func fillParsesHex() {
        let accent = Color.red
        #expect(ChatBannerChrome.fill(hex: "#112233", accent: accent) == Color(hex: "#112233"))
    }

    @Test("nil and unparseable text use white")
    func foregroundFallsBackToWhite() {
        #expect(ChatBannerChrome.foreground(hex: nil) == .white)
        #expect(ChatBannerChrome.foreground(hex: "not-a-color") == .white)
        #expect(ChatBannerChrome.foreground(hex: "#ffffff") == Color(hex: "#ffffff"))
    }
}
