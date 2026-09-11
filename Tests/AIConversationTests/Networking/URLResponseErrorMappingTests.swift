//
//  URLResponseErrorMappingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
import AIConversationCore

@Suite("URLResponse.mapError — validation envelope")
struct URLResponseErrorMappingTests {

    @Test("422 with params decodes as validation")
    func validation422() throws {
        let body = Data(#"""
        {
          "error": {
            "code": "validation_error",
            "message": "Please fix the highlighted fields.",
            "params": [
              { "field": "email", "message": "Enter a valid email." }
            ]
          }
        }
        """#.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 422,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            try response.mapError(body: body)
            Issue.record("expected validation error")
        } catch {
            guard case .http(.validation(let status, let message, let params)) = error else {
                Issue.record("expected validation, got \(error)")
                return
            }
            #expect(status == 422)
            #expect(message == "Please fix the highlighted fields.")
            #expect(params == [ValidationError(field: "email", message: "Enter a valid email.")])
        }
    }

    @Test("non-422 without params stays unhandled")
    func unhandledWithoutParams() throws {
        let body = Data(#"{"error":{"code":"oops","message":"Server blew up"}}"#.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        do {
            try response.mapError(body: body)
            Issue.record("expected unhandled")
        } catch {
            guard case .http(.unhandled(500)) = error else {
                Issue.record("expected unhandled(500), got \(error)")
                return
            }
        }
    }
}
