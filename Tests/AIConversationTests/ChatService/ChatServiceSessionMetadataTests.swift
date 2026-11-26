//
//  ChatServiceSessionMetadataTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// `PATCH /session` as `URLSession` sends it. `ScriptedURLProtocol` answers in process; no server
/// is involved.
@Suite("ChatService — session metadata PATCH on the wire")
struct ChatServiceSessionMetadataTests {

    @Test("metadata goes to PATCH /session with the bearer and the three SDK headers, keys verbatim")
    func patchesMetadata() async throws {
        let (sut, script) = Self.makeSUT(responses: [.init(body: Self.sessionState)])

        try await sut.patchSessionMetadata(.init(
            metadata: [
                "cseyeStoreSlug": .string("boozt-se"),
                "cart": .object(["itemCount": .int(2), "total": .double(49.5), "tags": .array([.string("sale")])]),
                "loggedIn": .bool(false),
                "coupon": .null
            ],
            signedMetadata: nil
        ))

        let request = try #require(script.requests.first)
        #expect(request.url?.path() == "/api/v1/chat/session")
        #expect(request.request.httpMethod == "PATCH")
        #expect(request.header("Authorization") == "Bearer host-token")
        #expect(request.header(ChatService.sdkPlatformHeader) == "ios")
        #expect(request.header(ChatService.sdkVersionHeader) == "9.8.7")
        #expect(request.header(ChatService.clientProfileHeader) == "product-recommendation")
        let json = try #require(request.json)
        #expect(json.keys.sorted() == ["metadata"])
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(metadata["cseyeStoreSlug"] as? String == "boozt-se")
        #expect(metadata["loggedIn"] as? Bool == false)
        #expect(metadata["coupon"] is NSNull)
        let cart = try #require(metadata["cart"] as? [String: Any])
        #expect(cart["itemCount"] as? Int == 2)
        #expect(cart["total"] as? Double == 49.5)
        #expect(cart["tags"] as? [String] == ["sale"])
    }

    @Test("a signed token goes as signed_metadata, alone")
    func patchesSignedMetadata() async throws {
        let (sut, script) = Self.makeSUT(responses: [.init(body: Self.sessionState)])

        try await sut.patchSessionMetadata(.init(metadata: nil, signedMetadata: "header.claims.signature"))

        let json = try #require(script.requests.first?.json)
        #expect(json.keys.sorted() == ["signed_metadata"])
        #expect(json["signed_metadata"] as? String == "header.claims.signature")
    }

    @Test("any 2xx counts as applied, whatever its body")
    func anySuccessCounts() async throws {
        let (sut, script) = Self.makeSUT(responses: [
            .init(status: 204),
            .init(body: Data(#"{"ok":true}"#.utf8))
        ])
        let request = SessionMetadataPatchRequest(metadata: ["screen": .string("pdp")], signedMetadata: nil)

        try await sut.patchSessionMetadata(request)
        try await sut.patchSessionMetadata(request)

        #expect(script.requests.count == 2)
    }

    @Test("a 401 keeps the token: the host is not asked for a new session")
    func unauthorizedKeepsToken() async throws {
        let providerCalls = Recorder<Void>()
        let (script, session) = ScriptedURLProtocol.make(responses: [.init(status: 401), .init(body: Self.sessionState)])
        let sut = ChatService(
            tokenProvider: {
                providerCalls.record(())
                return "host-token"
            },
            onResetConversation: { "reset-token" },
            onDeleteData: {},
            baseURL: ChatServiceFixtures.baseURL,
            session: session,
            sdkVersion: "9.8.7",
            clientProfiles: [.productRecommendation]
        )

        await #expect {
            try await sut.patchSessionMetadata(.init(metadata: nil, signedMetadata: "token"))
        } throws: { error in
            if case ChatServiceError.sessionExpired = error { true } else { false }
        }
        _ = try await sut.fetchSession()

        #expect(providerCalls.count == 1)
        #expect(script.requests.last?.header("Authorization") == "Bearer host-token")
    }

    @Test("a 422 surfaces as validation, a 409 as conflict and a 401 as sessionExpired")
    func errors() async {
        let rejected = Data(#"""
        { "error": { "code": "validation", "message": "Validation failed",
          "params": [{ "field": "signed_metadata", "message": "signed_metadata token has expired" }] } }
        """#.utf8)
        let (sut, _) = Self.makeSUT(responses: [
            .init(status: 422, body: rejected),
            .init(status: 409),
            .init(status: 401)
        ])
        let request = SessionMetadataPatchRequest(metadata: nil, signedMetadata: "expired")

        await #expect {
            try await sut.patchSessionMetadata(request)
        } throws: { error in
            if case ChatServiceError.validation(let message, let params) = error {
                message == "Validation failed"
                    && params == [.init(field: "signed_metadata", message: "signed_metadata token has expired")]
            } else {
                false
            }
        }
        await #expect {
            try await sut.patchSessionMetadata(request)
        } throws: { error in
            if case ChatServiceError.conflict = error { true } else { false }
        }
        await #expect {
            try await sut.patchSessionMetadata(request)
        } throws: { error in
            if case ChatServiceError.sessionExpired = error { true } else { false }
        }
    }
}

private extension ChatServiceSessionMetadataTests {

    static let sessionState = Data(#"{"values":[],"metadata":{"cseyeStoreSlug":"boozt-se"}}"#.utf8)

    static func makeSUT(
        responses: [ScriptedURLProtocol.Response]
    ) -> (ChatService, ScriptedURLProtocol.Script) {
        ChatServiceFixtures.makeSUT(responses: responses)
    }
}
