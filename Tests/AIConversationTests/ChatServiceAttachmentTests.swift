//
//  ChatServiceAttachmentTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// What actually leaves the device when a send carries attachments, asserted on the POST body
/// over a stubbed `URLSession` — the encoder tests cover the JSON shape, this covers the mapping.
@Suite("ChatService — attachments on the wire")
struct ChatServiceAttachmentTests {

    private let image = OutgoingAttachment(kind: .image, data: "aGVsbG8=", mime: "image/jpeg")

    @Test("text + image sends a text part followed by an image part with data and mime")
    func textAndImage() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [ChatServiceFixtures.done()])

        try await ChatServiceFixtures.drain(sut.sendMessage("what is this?", attachments: [self.image], page: "pdp"))

        let request = try #require(script.requests.first)
        let parts = try #require(Self.parts(of: request))
        #expect(request.url?.path() == "/api/v1/chat/messages")
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[0]["text"] as? String == "what is this?")
        #expect(parts[1]["type"] as? String == "image")
        #expect(parts[1]["data"] as? String == "aGVsbG8=")
        #expect(parts[1]["mime"] as? String == "image/jpeg")
        #expect(parts[1]["filename"] == nil, "no filename was given, so none must be invented")
        #expect((request.json?["context"] as? [String: Any])?["page"] as? String == "pdp")
    }

    @Test("image-only sends no text part")
    func imageOnly() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [ChatServiceFixtures.done()])

        try await ChatServiceFixtures.drain(sut.sendMessage("", attachments: [self.image], page: nil))

        let request = try #require(script.requests.first)
        let parts = try #require(Self.parts(of: request))
        #expect(parts.map { $0["type"] as? String } == ["image"])
        #expect(request.json?["context"] == nil)
    }

    @Test("a filename set by the caller is forwarded verbatim")
    func filenameForwarded() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [ChatServiceFixtures.done()])
        let named = OutgoingAttachment(kind: .image, data: "QQ==", mime: "image/png", filename: "receipt.png")

        try await ChatServiceFixtures.drain(sut.sendMessage("", attachments: [named], page: nil))

        let request = try #require(script.requests.first)
        let parts = try #require(Self.parts(of: request))
        #expect(parts[0]["filename"] as? String == "receipt.png")
    }

    // MARK: - fetchData

    @Test("fetchData decodes a data: URL inline and never touches the network")
    func dataURLShortCircuits() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: []) // any request would fail loudly
        let url = try #require(self.image.dataURL)

        let data = try await sut.fetchData(url)

        #expect(String(decoding: data, as: UTF8.self) == "hello")
        #expect(script.requests.isEmpty)
    }

    @Test("fetchData over http fetches without an Authorization header — signed URLs carry their own")
    func httpFetchIsUnauthenticated() async throws {
        let (sut, script) = ChatServiceFixtures.makeSUT(responses: [
            .init(body: Data([0xFF, 0xD8]), contentType: "image/jpeg")
        ])

        let data = try await sut.fetchData(URL(string: "https://cdn.example/a.jpg?token=abc")!)

        #expect(data == Data([0xFF, 0xD8]))
        let request = try #require(script.requests.first)
        #expect(request.header("Authorization") == nil)
    }

    // MARK: - Helpers

    private static func parts(of request: ScriptedURLProtocol.SeenRequest) -> [[String: Any]]? {
        (request.json?["message"] as? [String: Any])?["parts"] as? [[String: Any]]
    }
}
