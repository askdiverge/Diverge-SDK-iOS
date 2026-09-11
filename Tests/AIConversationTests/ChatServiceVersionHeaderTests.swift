//
//  ChatServiceVersionHeaderTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// The backend gates wire-contract changes on the SDK release, so every authenticated API call
/// must carry it — and the value must be the one `scripts/sync-version.sh` generates.
@Suite("ChatService — X-Diverge-SDK-Version header")
struct ChatServiceVersionHeaderTests {

    @Test("authenticated API calls carry the SDK version header")
    func headerOnSendAndConfig() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(sdkVersion: "9.8.7", responses: [
            ChatServiceFixtures.done(),
            .init(status: 200, body: Data(#"{"messages":[],"next_cursor":null}"#.utf8))
        ])

        try await ChatServiceFixtures.drain(sut.sendMessage("hello", page: nil))
        _ = try await sut.fetchHistory(cursor: nil)

        #expect(script.requests.count == 2)
        #expect(script.requests.allSatisfy { $0.header(ChatService.sdkVersionHeader) == "9.8.7" })
        #expect(script.requests.allSatisfy { $0.header("Authorization") == "Bearer host-token" })
    }

    @Test("without a version the header is omitted rather than sent empty")
    func noHeaderWhenUnset() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [ChatServiceFixtures.done()])

        try await ChatServiceFixtures.drain(sut.sendMessage("hello", page: nil))

        #expect(script.requests.first?.header(ChatService.sdkVersionHeader) == nil)
    }

    @Test("the generated VersionInfo is a SemVer string")
    func versionInfoIsSemVer() {
        let semver = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/
        #expect(VersionInfo.current.wholeMatch(of: semver) != nil)
    }
}
