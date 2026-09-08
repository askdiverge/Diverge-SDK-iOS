//
//  ChatServiceLivechatHandoverTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("ChatService — livechat handover on the wire")
struct ChatServiceLivechatHandoverTests {

    @Test("POST /livechat/handover sends bearer and client_context fields")
    func sendsClientContext() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(#"{"status":"waiting"}"#.utf8))
        ])
        let page = String(repeating: "p", count: 2100)
        let context = LivechatClientContext(
            browser: "Sample",
            browserLanguage: "en-US",
            browserVersion: "1.2.3",
            currentPageUrl: page,
            language: "en",
            os: "iOS"
        )

        try await sut.requestLivechatHandover(
            source: "manual_button",
            partId: nil,
            clientContext: context
        )

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/livechat/handover")
        #expect(request.request.httpMethod == "POST")
        #expect(request.header("Authorization") == "Bearer host-token")
        let json = try #require(request.json)
        #expect(json["platform"] as? String == "mobile_app")
        #expect(json["source"] as? String == "manual_button")
        let ctx = try #require(json["client_context"] as? [String: Any])
        #expect(ctx["os"] as? String == "iOS")
        #expect(ctx["browser"] as? String == "Sample")
        #expect(ctx["browser_version"] as? String == "1.2.3")
        #expect(ctx["browser_language"] as? String == "en-US")
        #expect(ctx["language"] as? String == "en")
        let url = try #require(ctx["current_page_url"] as? String)
        #expect(url.count == 2048)
    }

    @Test("empty client_context keys are omitted from the body")
    func omitsEmptyKeys() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(#"{"status":"waiting"}"#.utf8))
        ])
        let context = LivechatClientContext(browserLanguage: "da", os: "iOS")

        try await sut.requestLivechatHandover(
            source: "assistant_marker",
            partId: "part_1",
            clientContext: context
        )

        let ctx = try #require(script.requests.first?.json?["client_context"] as? [String: Any])
        #expect(ctx["os"] as? String == "iOS")
        #expect(ctx["browser_language"] as? String == "da")
        #expect(ctx["browser"] == nil)
        #expect(ctx["current_page_url"] == nil)
        #expect(script.requests.first?.json?["part_id"] as? String == "part_1")
    }

    @Test("nil client_context omits the key entirely")
    func nilContextOmitted() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(status: 200, body: Data(#"{"status":"waiting"}"#.utf8))
        ])

        try await sut.requestLivechatHandover(
            source: "manual_button",
            partId: nil,
            clientContext: nil
        )

        let json = try #require(script.requests.first?.json)
        #expect(json["client_context"] == nil)
    }
}

@Suite("LivechatClientContext")
struct LivechatClientContextTests {

    @Test("native builder fills os and truncates the page")
    func nativeBuilder() {
        let long = String(repeating: "x", count: 3000)
        let context = LivechatClientContext.native(
            page: long,
            preferredLanguages: ["sv-SE"]
        )
        #expect(context.os == "iOS" || context.os == "macOS")
        #expect(context.browserLanguage == "sv-SE")
        #expect(context.currentPageUrl?.count == 2048)
    }

    @Test("init truncates 255-char fields and omits whitespace-only page")
    func truncatesFieldsAndOmitsBlankPage() {
        let long = String(repeating: "b", count: 300)
        let context = LivechatClientContext(browser: long, currentPageUrl: "   ", os: long)
        #expect(context.browser?.count == 255)
        #expect(context.os?.count == 255)
        #expect(context.currentPageUrl == nil)
    }
}
