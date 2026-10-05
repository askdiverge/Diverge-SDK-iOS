//
//  URLResponseErrorMappingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationCore

/// Pins that the transport layer passes a rejected request's status and body up unchanged, so
/// only the facade interprets the API's error envelope.
@Suite("URLResponse.mapError — status and body")
struct URLResponseErrorMappingTests {

    @Test("a rejected request carries its status and body", arguments: [409, 422, 500])
    func rejectedCarriesBody(status: Int) throws {
        let body = Data(#"{"error":{"code":"validation","message":"Validation failed"}}"#.utf8)

        do {
            try self.makeResponse(status: status).mapError(body: body)
            Issue.record("expected unhandled")
        } catch NetworkError.http(.unhandled(let code, let carried)) {
            #expect(code == status)
            #expect(carried == body)
        } catch {
            Issue.record("expected unhandled(\(status)), got \(error)")
        }
    }

    @Test("a 401 maps to unauthorized")
    func unauthorized() {
        #expect(throws: NetworkError.self) {
            try self.makeResponse(status: 401).mapError(body: Data())
        }
    }

    // MARK: - Fixtures

    private func makeResponse(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
