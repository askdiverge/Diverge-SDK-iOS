//
//  ChatConfigDecodingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins `ChatConfig` fields against the shapes the Chatbot API TypeSpec allows. A field the spec
/// declares nullable must decode `null`: `/config` is decoded as one value, so a single mismatch
/// fails bootstrap and shows the host "Assistant Unavailable".
@Suite("ChatConfig — decoding against the API contract")
struct ChatConfigDecodingTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("a header logo url of null decodes to no logo")
    func headerLogoNull() throws {
        let header = try self.decodeHeader(logoURL: "null")

        #expect(header.logo.url == nil)
    }

    @Test("a header logo url decodes to the URL")
    func headerLogoURL() throws {
        let header = try self.decodeHeader(logoURL: #""https://cdn.example.com/logo.png""#)

        #expect(header.logo.url == URL(string: "https://cdn.example.com/logo.png"))
    }

    // MARK: - Fixtures

    private func decodeHeader(logoURL: String) throws -> ChatConfig.Theme.Header {
        let json = """
        {
          "alignment": "center",
          "logo": { "url": \(logoURL) },
          "button": { "background_color": "#F2F0EF", "icon_color": "#000000" }
        }
        """
        return try self.decoder.decode(ChatConfig.Theme.Header.self, from: Data(json.utf8))
    }
}
