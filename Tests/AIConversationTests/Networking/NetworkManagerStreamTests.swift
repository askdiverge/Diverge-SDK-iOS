//
//  NetworkManagerStreamTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation
import Testing
import AIConversationCore

@Suite("NetworkManager.stream — SSE end-to-end", .serialized)
struct NetworkManagerStreamTests {

    @Test("Single SSE frame yields a decoded envelope")
    func singleFrameYieldsDecodedEnvelope() async throws {
        let body = "event: status\ndata: {\"value\":\"connected\"}\n\n"
        let sut = makeSUT(sseBody: body)

        let frames = try await collect(Frame.self, from: sut)

        #expect(frames == [Frame(type: "status", data: ["value": "connected"])])
    }

    @Test("Multiple SSE frames yield decoded envelopes in order")
    func multipleFramesYieldOrderedEnvelopes() async throws {
        let body = "event: status\ndata: {\"value\":\"connected\"}\n\n"
                 + "event: status\ndata: {\"value\":\"processing\"}\n\n"
                 + "event: message\ndata: {\"value\":\"hello world\"}\n\n"
        let sut = makeSUT(sseBody: body)

        let frames = try await collect(Frame.self, from: sut)

        #expect(frames == [
            Frame(type: "status", data: ["value": "connected"]),
            Frame(type: "status", data: ["value": "processing"]),
            Frame(type: "message", data: ["value": "hello world"])
        ])
    }

    @Test("Comment lines are ignored")
    func commentLinesAreIgnored() async throws {
        let body = ": this is a keep-alive comment\n"
                 + "event: status\n"
                 + ": another comment between fields\n"
                 + "data: {\"value\":\"connected\"}\n\n"
        let sut = makeSUT(sseBody: body)

        let frames = try await collect(Frame.self, from: sut)

        #expect(frames == [Frame(type: "status", data: ["value": "connected"])])
    }

    @Test("Multi-line data fields are joined with newline before decoding")
    func multiLineDataIsJoined() async throws {
        let body = "event: message\n"
                 + "data: {\"value\":\n"
                 + "data: \"split\"}\n\n"
        let sut = makeSUT(sseBody: body)

        let frames = try await collect(Frame.self, from: sut)

        #expect(frames == [Frame(type: "message", data: ["value": "split"])])
    }

    @Test("Non-2xx HTTP status throws NetworkError.http(.unhandled)")
    func non2xxStatusThrows() async throws {
        let sut = makeSUT(sseBody: "", statusCode: 500)

        do {
            _ = try await collect(Frame.self, from: sut)
            Issue.record("Expected stream to throw")
        } catch let error as NetworkError {
            guard case .http(.unhandled(let code)) = error, code == 500 else {
                Issue.record("Expected .http(.unhandled(500)), got \(error)")
                return
            }
        }
    }

    @Test("401 HTTP status throws NetworkError.http(.unauthorized)")
    func unauthorizedStatusThrows() async throws {
        let sut = makeSUT(sseBody: "", statusCode: 401)

        do {
            _ = try await collect(Frame.self, from: sut)
            Issue.record("Expected stream to throw")
        } catch let error as NetworkError {
            guard case .http(.unauthorized) = error else {
                Issue.record("Expected .http(.unauthorized), got \(error)")
                return
            }
        }
    }

    // MARK: - SUT

    private func makeSUT(sseBody: String, statusCode: Int = 200) -> NetworkManager {
        MockURLProtocol.responseBody = Data(sseBody.utf8)
        MockURLProtocol.statusCode = statusCode

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)

        return NetworkManager(
            decoder: JSONDecoder(),
            encoder: JSONEncoder(),
            session: session
        )
    }

    private func collect<Event: Decodable & Sendable>(
        _ eventType: Event.Type,
        from sut: NetworkManager
    ) async throws -> [Event] {
        let stream: AsyncThrowingStream<Event, any Error> = sut.stream(
            url: URL(string: "https://test.example/sse")!,
            payload: EmptyPayload(),
            headers: nil
        )
        var events: [Event] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

// MARK: - Test fixtures

private struct Frame: Decodable, Sendable, Equatable {
    let type: String
    let data: [String: String]
}

private struct EmptyPayload: Encodable, Sendable {}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var responseBody: Data = .init()
    nonisolated(unsafe) static var statusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
