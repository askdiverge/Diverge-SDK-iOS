//
//  ChatServiceHeaderTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
import AIConversationEngine

/// The backend logs adoption on the SDK release and picks its tool set from the capability
/// profile, so both headers have to reach every authenticated call — and the profile's raw
/// value is a wire contract that must not drift.
@Suite("ChatService — version and profile headers")
struct ChatServiceHeaderTests {

    @Test("a GET carries the SDK version and the client profile")
    func historyCarriesHeaders() async throws {
        let (sut, recorder) = makeSUT(body: #"{"messages":[],"next_cursor":null}"#)

        _ = try await sut.fetchHistory(cursor: nil)

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == "Bearer token-1")
        #expect(request.header(ChatService.sdkVersionHeader) == "9.8.7")
        #expect(request.header(ChatService.clientProfileHeader) == "product-recommendation")
    }

    @Test("the SSE send carries them too, without losing its own Accept override")
    func sendCarriesHeaders() async throws {
        let (sut, recorder) = makeSUT(body: "", contentType: "text/event-stream")

        for try await _ in sut.sendMessage("hello", page: nil) {}

        let request = try #require(recorder.requests.first)
        #expect(request.header(ChatService.sdkVersionHeader) == "9.8.7")
        #expect(request.header(ChatService.clientProfileHeader) == "product-recommendation")
        #expect(request.header("Accept") == "text/event-stream")
    }

    @Test("unset values omit the headers rather than sending them empty")
    func omittedWhenUnset() async throws {
        let (sut, recorder) = makeSUT(
            body: #"{"messages":[],"next_cursor":null}"#,
            sdkVersion: nil,
            clientProfile: nil
        )

        _ = try await sut.fetchHistory(cursor: nil)

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == "Bearer token-1")
        #expect(request.header(ChatService.sdkVersionHeader) == nil)
        #expect(request.header(ChatService.clientProfileHeader) == nil)
    }

    @Test("unauthenticated asset downloads stay header-less")
    func assetDownloadsCarryNothing() async throws {
        let (sut, recorder) = makeSUT(body: "font-bytes")

        _ = try await sut.fetchData(URL(string: "https://cdn.example/font.otf")!)

        let request = try #require(recorder.requests.first)
        #expect(request.header("Authorization") == nil)
        #expect(request.header(ChatService.sdkVersionHeader) == nil)
        #expect(request.header(ChatService.clientProfileHeader) == nil)
    }

    // MARK: - Contract

    @Test("the profile raw value is the string the backend gates on")
    func profileRawValueIsStable() {
        #expect(ClientProfile.productRecommendation.rawValue == "product-recommendation")
    }

    @Test("AIChat sends the version scripts/sync-version.sh generated from VERSION")
    func versionInfoIsSemVer() {
        let semver = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/
        #expect(VersionInfo.current.wholeMatch(of: semver) != nil)
    }

    // MARK: - SUT

    private func makeSUT(
        body: String,
        contentType: String = "application/json",
        sdkVersion: String? = "9.8.7",
        clientProfile: ClientProfile? = .productRecommendation
    ) -> (ChatService, RecordingURLProtocol.Recorder) {
        let (session, recorder) = RecordingURLProtocol.makeSession(
            stub: .init(body: Data(body.utf8), contentType: contentType)
        )

        let sut = ChatService(
            tokenProvider: { "token-1" },
            onResetConversation: { "token-2" },
            onDeleteData: {},
            session: session,
            sdkVersion: sdkVersion,
            clientProfile: clientProfile
        )

        return (sut, recorder)
    }
}
