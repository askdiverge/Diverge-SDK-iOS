//
//  ChatViewModelBannerTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — in-chat banners")
@MainActor
struct ChatViewModelBannerTests {

    @Test("visibleBanners drops dismissed fingerprints")
    func dismissHidesUntilRelaunch() {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        let banner = ChatBanner(
            id: "1",
            message: "Promo",
            backgroundColor: "#111",
            dismissible: true
        )
        viewModel.setBannersForTesting([banner])
        #expect(viewModel.visibleBanners.count == 1)

        viewModel.dismissBanner(banner)
        #expect(viewModel.visibleBanners.isEmpty)

        // Same content after re-set stays dismissed (in-memory for this AIChat).
        viewModel.setBannersForTesting([banner])
        #expect(viewModel.visibleBanners.isEmpty)

        // Content change → new fingerprint → visible again.
        let updated = ChatBanner(
            id: "1",
            message: "Promo v2",
            backgroundColor: "#111",
            dismissible: true
        )
        viewModel.setBannersForTesting([updated])
        #expect(viewModel.visibleBanners.map(\.message) == ["Promo v2"])
    }

    @Test("loadBanners soft-fails to empty on missing route")
    func softFailEmpty() async throws {
        let (service, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 404, body: Data())
        ])
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: { "/products" },
            conversationFlow: .topDown
        )
        viewModel.setBannersForTesting([
            ChatBanner(id: "stale", message: "should clear")
        ])
        try await viewModel.loadBanners(url: "/products")
        #expect(viewModel.banners.isEmpty)
        #expect(viewModel.visibleBanners.isEmpty)
        #expect(viewModel.sessionEnded == false)
    }

    @Test("loadBanners installs the decoded list")
    func loadSuccess() async throws {
        let body = Data(#"""
        {"banners":[{"id":"3","message":"Hello","dismissible":false}]}
        """#.utf8)
        let (service, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: body)
        ])
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: { "https://shop.example.com/products" },
            conversationFlow: .topDown
        )
        try await viewModel.loadBanners(url: "https://shop.example.com/products")
        #expect(viewModel.banners.map(\.message) == ["Hello"])
        let request = try #require(script.requests.first)
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        #expect(items.contains(
            URLQueryItem(name: "url", value: "https://shop.example.com/products")
        ))
    }

    @Test("loadBanners 401 surfaces SessionEnded and does not install banners")
    func unauthorizedEndsSession() async {
        let (service, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: { "/products" },
            conversationFlow: .topDown
        )
        viewModel.setBannersForTesting([
            ChatBanner(id: "stale", message: "should clear")
        ])
        do {
            try await viewModel.loadBanners(url: "/products")
            Issue.record("expected SessionEnded")
        } catch is ChatView.SessionEnded {
            #expect(viewModel.banners.isEmpty)
            #expect(viewModel.sessionEnded == true)
        } catch {
            Issue.record("expected SessionEnded, got \(error)")
        }
    }

    @Test("visibleBanners drops blank messages")
    func blankMessageHidden() {
        let viewModel = ChatView.ViewModel.forTesting(provider: StubChatProviding())
        viewModel.setBannersForTesting([
            ChatBanner(id: "1", message: "   "),
            ChatBanner(id: "2", message: "Hello")
        ])
        #expect(viewModel.visibleBanners.map(\.id) == ["2"])
    }
}
