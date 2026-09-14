//
//  ChatServiceBaseURLTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
import AIConversationEngine

@Suite("ChatService — API base URL")
struct ChatServiceBaseURLTests {

    @Test("the default host is production")
    func defaultsToProduction() async throws {
        let (sut, recorder) = makeSUT(baseURL: nil)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("https://api.dialogintelligens.dk/api/v1/chat/messages"))
    }

    @Test("an override changes the host and keeps the endpoint path")
    func overrideChangesHostOnly() async throws {
        let (sut, recorder) = makeSUT(baseURL: URL(string: "http://127.0.0.1:3000")!)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("http://127.0.0.1:3000/api/v1/chat/messages"))
    }

    @Test("an override with a path prefix is preserved")
    func overrideKeepsPathPrefix() async throws {
        let (sut, recorder) = makeSUT(baseURL: URL(string: "https://gateway.example/diverge")!)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("https://gateway.example/diverge/api/v1/chat/messages"))
    }

    // MARK: - Contract

    @Test("DivergeAPI and the engine facade share one production constant")
    func productionConstantIsSingleSource() {
        #expect(DivergeAPI.productionBaseURL == ChatService.productionBaseURL)
        #expect(DivergeAPI.productionBaseURL.absoluteString == "https://api.dialogintelligens.dk")
    }

    @Test("a Configuration that says nothing about the host gets production")
    func configurationDefaultsToProduction() {
        let configuration = AIChat.Configuration(
            tokenProvider: { "token" },
            resetConversation: { "token" },
            deleteData: {}
        )

        #expect(configuration.apiBaseURL == DivergeAPI.productionBaseURL)
    }

    // MARK: - SUT

    private func makeSUT(baseURL: URL?) -> (ChatService, RecordingURLProtocol.Recorder) {
        let (session, recorder) = RecordingURLProtocol.makeSession(
            stub: .init(body: Data(#"{"messages":[],"next_cursor":null}"#.utf8))
        )

        let sut = baseURL.map { url in
            ChatService(
                tokenProvider: { "token-1" },
                onResetConversation: { "token-2" },
                onDeleteData: {},
                baseURL: url,
                session: session
            )
        } ?? ChatService(
            tokenProvider: { "token-1" },
            onResetConversation: { "token-2" },
            onDeleteData: {},
            session: session
        )

        return (sut, recorder)
    }
}
