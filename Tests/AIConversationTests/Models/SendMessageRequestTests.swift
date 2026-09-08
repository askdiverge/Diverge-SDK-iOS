//
//  SendMessageRequestTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("SendMessageRequest — image/file parts")
struct SendMessageRequestTests {

    @Test("text + image parts encode with data/mime/filename keys")
    func textAndImageEncode() throws {
        let request = SendMessageRequest(
            message: .init(parts: [
                .text("see this"),
                .image(.init(data: "aGVsbG8=", mime: "image/jpeg", filename: "receipt.jpg"))
            ]),
            context: nil
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        let parts = (json?["message"] as? [String: Any])?["parts"] as? [[String: Any]]
        #expect(parts?.count == 2)
        #expect(parts?[0]["type"] as? String == "text")
        #expect(parts?[0]["text"] as? String == "see this")
        #expect(parts?[1]["type"] as? String == "image")
        #expect(parts?[1]["data"] as? String == "aGVsbG8=")
        #expect(parts?[1]["mime"] as? String == "image/jpeg")
        #expect(parts?[1]["filename"] as? String == "receipt.jpg")
    }

    @Test("image-only message encodes without a text part")
    func imageOnlyEncode() throws {
        let request = SendMessageRequest(
            message: .init(parts: [
                .image(.init(data: "QQ==", mime: "image/png", filename: nil))
            ]),
            context: nil
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        let parts = (json?["message"] as? [String: Any])?["parts"] as? [[String: Any]]
        #expect(parts?.count == 1)
        #expect(parts?[0]["type"] as? String == "image")
        #expect(parts?[0]["filename"] as? String == nil)
    }
}
