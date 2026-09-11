//
//  ChatBannerTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatBanner decode + CTA gate")
struct ChatBannerTests {

    @Test("decodes a full banner with snake_case keys")
    func decodesFull() throws {
        let json = Data(#"""
        {
          "id": "42",
          "message": "Sale on now",
          "background_color": "#112233",
          "text_color": "#ffffff",
          "cta_url": "https://shop.example.com/sale",
          "cta_label": "Shop now",
          "cta_style": "button",
          "dismissible": true
        }
        """#.utf8)
        let decoder = JSONDecoder.wire()
        let banner = try decoder.decode(ChatBanner.self, from: json)
        #expect(banner.id == "42")
        #expect(banner.message == "Sale on now")
        #expect(banner.backgroundColor == "#112233")
        #expect(banner.ctaStyle == .button)
        #expect(banner.dismissible == true)
        #expect(banner.showsCTA == true)
    }

    @Test("missing optional fields stay nil and dismissible defaults false")
    func lenientOptionals() throws {
        let json = Data(#"""
        { "id": "1", "message": "Hello" }
        """#.utf8)
        let decoder = JSONDecoder.wire()
        let banner = try decoder.decode(ChatBanner.self, from: json)
        #expect(banner.backgroundColor == nil)
        #expect(banner.ctaUrl == nil)
        #expect(banner.ctaStyle == nil)
        #expect(banner.dismissible == false)
        #expect(banner.showsCTA == false)
    }

    @Test("CTA hidden when only label or only URL is present")
    func ctaRequiresBoth() {
        let labelOnly = ChatBanner(id: "1", message: "x", ctaUrl: nil, ctaLabel: "Go")
        let urlOnly = ChatBanner(id: "2", message: "x", ctaUrl: "https://example.com", ctaLabel: nil)
        let blankLabel = ChatBanner(id: "3", message: "x", ctaUrl: "https://example.com", ctaLabel: "  ")
        let both = ChatBanner(id: "4", message: "x", ctaUrl: "https://example.com/a", ctaLabel: "Go")
        #expect(labelOnly.showsCTA == false)
        #expect(urlOnly.showsCTA == false)
        #expect(blankLabel.showsCTA == false)
        #expect(both.showsCTA == true)
    }

    @Test("relative and javascript URLs are rejected")
    func rejectsUnsafeCTA() {
        let relative = ChatBanner(id: "1", message: "x", ctaUrl: "/sale", ctaLabel: "Go")
        let js = ChatBanner(id: "2", message: "x", ctaUrl: "javascript:alert(1)", ctaLabel: "Go")
        #expect(relative.sanitizedCTAURL == nil)
        #expect(js.sanitizedCTAURL == nil)
        #expect(relative.showsCTA == false)
        #expect(js.showsCTA == false)
    }

    @Test("unknown and blank cta_style decode as nil")
    func unknownCTAStyleIsNil() throws {
        let decoder = JSONDecoder.wire()
        for raw in [#""pill""#, #""""#] {
            let json = Data("""
            { "id": "1", "message": "Hi", "cta_style": \(raw) }
            """.utf8)
            let banner = try decoder.decode(ChatBanner.self, from: json)
            #expect(banner.ctaStyle == nil)
            #expect(banner.message == "Hi")
        }
    }

    @Test("content fingerprint matches web field order")
    func fingerprint() {
        let banner = ChatBanner(
            id: "9",
            message: "Hi",
            backgroundColor: "#000",
            textColor: "#fff",
            ctaUrl: "https://example.com",
            ctaLabel: "Go",
            ctaStyle: .link,
            dismissible: true
        )
        #expect(banner.contentFingerprint == "Hi|#000|#fff|https://example.com|Go|link|1")
    }

    @Test("lossy list keeps good rows and drops blank messages")
    func lossyListDropsBadAndBlank() throws {
        let json = Data(#"""
        {
          "banners": [
            { "id": "1", "message": "Good" },
            { "message": "missing id" },
            { "id": "2", "message": "   " },
            { "id": "3", "message": "Also good", "cta_style": "pill" }
          ]
        }
        """#.utf8)
        let decoder = JSONDecoder.wire()
        let list = try decoder.decode(ChatBannerList.self, from: json)
        #expect(list.banners.map(\.id) == ["1", "3"])
        #expect(list.banners[1].ctaStyle == nil)
    }
}

@Suite("ChatService — banners on the wire")
struct ChatServiceBannerTests {

    private static let listJSON = Data(#"""
    {
      "banners": [
        {
          "id": "7",
          "message": "Free shipping",
          "background_color": "#4F46E5",
          "text_color": null,
          "cta_url": "https://shop.example.com/shipping",
          "cta_label": "Learn more",
          "cta_style": "link",
          "dismissible": true
        }
      ]
    }
    """#.utf8)

    @Test("GET /banners sends bearer and url query from contextProvider page")
    func fetchesWithURLQuery() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Self.listJSON)
        ])

        let banners = try await sut.fetchBanners(url: "https://shop.example.com/products/1")

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/banners")
        #expect(request.request.httpMethod == "GET")
        #expect(request.header("Authorization") == "Bearer host-token")
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "url", value: "https://shop.example.com/products/1")))
        #expect(banners.count == 1)
        #expect(banners[0].message == "Free shipping")
        #expect(banners[0].dismissible == true)
    }

    @Test("nil/empty url omits the query parameter")
    func omitsEmptyURL() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(#"{"banners":[]}"#.utf8))
        ])

        _ = try await sut.fetchBanners(url: nil)
        let request = try #require(script.requests.first)
        #expect(request.url?.query() == nil || request.url?.query()?.isEmpty == true)

        let (sut2, script2) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(#"{"banners":[]}"#.utf8))
        ])
        _ = try await sut2.fetchBanners(url: "")
        let request2 = try #require(script2.requests.first)
        #expect(request2.url?.query() == nil || request2.url?.query()?.isEmpty == true)
    }

    @Test("404 on /banners surfaces as transport (VM soft-fails)")
    func missingRouteIsTransport() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 404, body: Data())
        ])

        do {
            _ = try await sut.fetchBanners(url: "/products")
            Issue.record("expected transport error")
        } catch ChatServiceError.transport {
            // expected — ViewModel.loadBanners catches this
        } catch {
            Issue.record("expected transport, got \(error)")
        }
    }

    @Test("401 on /banners surfaces as sessionExpired")
    func unauthorizedSurfacesExpiry() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 401, body: Data())
        ])

        do {
            _ = try await sut.fetchBanners(url: nil)
            Issue.record("expected sessionExpired")
        } catch ChatServiceError.sessionExpired {
            // expected
        } catch {
            Issue.record("expected sessionExpired, got \(error)")
        }
    }
}
