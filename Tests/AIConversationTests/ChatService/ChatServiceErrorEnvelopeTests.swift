//
//  ChatServiceErrorEnvelopeTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins how the facade reads the API's error envelope on endpoints other than `/actions`.
/// Responses come from `ScriptedURLProtocol`; no server is involved.
@Suite("ChatService — API error envelope")
struct ChatServiceErrorEnvelopeTests {

    @Test("a 422 before the message stream starts surfaces its field errors")
    func messageValidationSurfaces() async throws {
        let body = Data(#"""
        {
          "error": {
            "code": "validation",
            "message": "Validation failed",
            "params": [{ "field": "message.parts.0.text", "message": "Text is required" }]
          }
        }
        """#.utf8)
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 422, body: body)])

        do {
            try await ChatServiceFixtures.drain(sut.sendMessage("", page: nil))
            Issue.record("expected validation")
        } catch ChatServiceError.validation(let message, let params) {
            #expect(message == "Validation failed")
            #expect(params == [ValidationError(field: "message.parts.0.text", message: "Text is required")])
        } catch {
            Issue.record("expected validation, got \(error)")
        }
    }

    @Test("a 409 outside /actions stays a transport error")
    func conflictOutsideActionsIsTransport() async throws {
        let (sut, _) = ChatServiceFixtures.makeSUT(responses: [.init(status: 409, body: Data())])

        do {
            _ = try await sut.fetchHistory(cursor: nil)
            Issue.record("expected a transport error")
        } catch ChatServiceError.transport(.http(.unhandled(409, _))) {
            // expected
        } catch {
            Issue.record("expected transport(.http(.unhandled(409))), got \(error)")
        }
    }
}
