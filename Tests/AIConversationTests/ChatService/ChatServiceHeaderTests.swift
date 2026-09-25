//
//  ChatServiceHeaderTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
import AIConversationEngine

@Suite("ChatService — version and profile headers")
struct ChatServiceHeaderTests {

    @Test("a GET identifies the SDK platform and version and declares the client profile")
    func historyCarriesHeaders() async throws {
        let (sut, recorder) = makeSUT(body: #"{"messages":[],"next_cursor":null}"#)

        _ = try await sut.fetchHistory(cursor: nil)

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == "Bearer token-1")
        #expect(request.header(ChatService.sdkPlatformHeader) == "ios")
        #expect(request.header(ChatService.sdkVersionHeader) == "9.8.7")
        #expect(request.header(ChatService.clientProfileHeader) == "product-recommendation")
    }

    @Test("the SSE send carries them too, without losing its own Accept override")
    func sendCarriesHeaders() async throws {
        let (sut, recorder) = makeSUT(body: "", contentType: "text/event-stream")

        for try await _ in sut.sendMessage("hello", page: nil) {}

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == "Bearer token-1")
        #expect(request.header(ChatService.sdkPlatformHeader) == "ios")
        #expect(request.header(ChatService.sdkVersionHeader) == "9.8.7")
        #expect(request.header(ChatService.clientProfileHeader) == "product-recommendation")
        #expect(request.header("Accept") == "text/event-stream")
    }

    @Test("unauthenticated asset downloads carry only the request")
    func assetDownloadsCarryNothing() async throws {
        let (sut, recorder) = makeSUT(body: "font-bytes")

        _ = try await sut.fetchData(URL(string: "https://cdn.example/font.otf")!)

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == nil)
        #expect(request.header(ChatService.sdkPlatformHeader) == nil)
        #expect(request.header(ChatService.sdkVersionHeader) == nil)
        #expect(request.header(ChatService.clientProfileHeader) == nil)
    }

    // MARK: - Contract

    @Test("header names and values are the strings the backend reads")
    func wireLiteralsAreStable() {
        #expect(ChatService.sdkPlatformHeader == "X-Diverge-SDK-Platform")
        #expect(ChatService.sdkPlatform == "ios")
        #expect(ChatService.sdkVersionHeader == "X-Diverge-SDK-Version")
        #expect(ChatService.clientProfileHeader == "X-Diverge-Client-Profile")
        #expect(ClientProfile.productRecommendation.rawValue == "product-recommendation")
    }

    @Test("VersionInfo.current matches SemVer from VERSION")
    func versionInfoIsSemVer() {
        let semver = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/
        #expect(VersionInfo.current.wholeMatch(of: semver) != nil)
    }

    // MARK: - SUT

    private func makeSUT(
        body: String,
        contentType: String = "application/json"
    ) -> (ChatService, RecordingURLProtocol.Recorder) {
        let (session, recorder) = RecordingURLProtocol.makeSession(
            stub: .init(body: Data(body.utf8), contentType: contentType)
        )

        let sut = ChatService(
            tokenProvider: { "token-1" },
            onResetConversation: { "token-2" },
            onDeleteData: {},
            session: session,
            sdkVersion: "9.8.7",
            clientProfile: .productRecommendation
        )

        return (sut, recorder)
    }
}
