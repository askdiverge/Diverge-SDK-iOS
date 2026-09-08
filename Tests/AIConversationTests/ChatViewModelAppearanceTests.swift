//
//  ChatViewModelAppearanceTests.swift
//  AIConversationTests
//

import SwiftUI
import Testing
@testable import AIConversation

@Suite("ChatView.ViewModel — appearance preference")
@MainActor
struct ChatViewModelAppearanceTests {

    @Test("system mirrors the environment both ways")
    func systemMirrorsEnvironment() {
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            appearancePreference: .system
        )
        #expect(viewModel.resolvedScheme(environment: .light) == .light)
        #expect(viewModel.resolvedScheme(environment: .dark) == .dark)
        #expect(viewModel.preferredColorScheme(for: nil) == nil)
    }

    @Test("light stays light in a dark environment")
    func lightLocksLight() {
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            appearancePreference: .light
        )
        #expect(viewModel.resolvedScheme(environment: .dark) == .light)
        #expect(viewModel.resolvedScheme(environment: .light) == .light)
    }

    @Test("dark stays dark in a light environment")
    func darkLocksDark() {
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            appearancePreference: .dark
        )
        #expect(viewModel.resolvedScheme(environment: .light) == .dark)
        #expect(viewModel.resolvedScheme(environment: .dark) == .dark)
    }

    @Test("cloned dark_theme does not force dark chrome, even under a .dark lock")
    func clonedPaletteKeepsLightChrome() {
        let clone = ChatAppearance.default.with(colorScheme: .dark)
        #expect(clone.hasDistinctDarkPalette == false)
        for preference: AIChat.Appearance in [.system, .light, .dark] {
            let viewModel = ChatView.ViewModel.forTesting(
                provider: StubChatProviding(),
                appearancePreference: preference
            )
            #expect(viewModel.preferredColorScheme(for: clone) == .light)
        }
    }

    @Test("a distinct dark palette forces dark chrome when that slot is active")
    func distinctDarkForcesDarkChrome() {
        let distinct = ChatAppearance(
            light: .default,
            dark: .default,
            colorScheme: .dark,
            fontFamily: nil,
            hasDistinctDarkPalette: true
        )
        let viewModel = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            appearancePreference: .dark
        )
        #expect(viewModel.preferredColorScheme(for: distinct) == .dark)
        #expect(viewModel.preferredColorScheme(for: distinct.with(colorScheme: .light)) == .light)
        #expect(viewModel.preferredColorScheme(for: nil) == nil)
    }
}
