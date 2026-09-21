//
//  ChatServiceBaseURLTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
import AIConversationEngine

/// No network is involved: `RecordingURLProtocol` intercepts at the `URLProtocol` layer and
/// replays a scripted response, so these tests only assert the URL the SDK *builds*.
@Suite("ChatService — API environment")
struct ChatServiceBaseURLTests {

    @Test("the default host is production")
    func defaultsToProduction() async throws {
        let (sut, recorder) = makeSUT(baseURL: nil)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("https://api.dialogintelligens.dk/api/v1/chat/messages"))
    }

    @Test("the development environment changes the host and keeps the endpoint path")
    func developmentChangesHostOnly() async throws {
        let (sut, recorder) = makeSUT(baseURL: DivergeAPI.Environment.development.baseURL)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("https://dev.api.dialogintelligens.dk/api/v1/chat/messages"))
    }

    @Test("a host with a path prefix keeps it in front of the endpoint")
    func baseURLKeepsPathPrefix() async throws {
        let (sut, recorder) = makeSUT(baseURL: URL(string: "https://gateway.example/diverge")!)

        _ = try await sut.fetchHistory(cursor: nil)

        let url = try #require(recorder.requests.first?.url)
        #expect(url.absoluteString.hasPrefix("https://gateway.example/diverge/api/v1/chat/messages"))
    }

    // MARK: - Contract

    @Test("each environment maps to a Diverge host over https")
    func environmentsMapToDivergeHosts() {
        #expect(DivergeAPI.Environment.production.baseURL == ChatService.productionBaseURL)
        #expect(DivergeAPI.Environment.development.baseURL == ChatService.developmentBaseURL)
        #expect(ChatService.productionBaseURL.absoluteString == "https://api.dialogintelligens.dk")
        #expect(ChatService.developmentBaseURL.absoluteString == "https://dev.api.dialogintelligens.dk")
    }

    @Test("a Configuration that says nothing about the environment gets production")
    func configurationDefaultsToProduction() {
        let configuration = AIChat.Configuration(
            tokenProvider: { "token" },
            resetConversation: { "token" },
            deleteData: {}
        )

        #expect(configuration.environment == .production)
    }

    // MARK: - SUT

    private func makeSUT(baseURL: URL?) -> (ChatService, RecordingURLProtocol.Recorder) {
        let (session, recorder) = RecordingURLProtocol.makeSession(
            stub: .init(body: Data(#"{"messages":[],"next_cursor":null}"#.utf8))
        )

        let sut = ChatService(
            tokenProvider: { "token-1" },
            onResetConversation: { "token-2" },
            onDeleteData: {},
            baseURL: baseURL ?? ChatService.productionBaseURL,
            session: session,
            sdkVersion: "9.8.7",
            clientProfile: .productRecommendation
        )

        return (sut, recorder)
    }
}
