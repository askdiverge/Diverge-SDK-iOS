//
//  ScriptedURLProtocol.swift
//  AIConversationTests
//

import Foundation

/// Stubs `URLSession` for end-to-end tests. Each ``Script`` owns a queue of responses (served in
/// order, repeating the last once the queue runs dry) and records every request it saw, body
/// included. Scripts are bound to the session `make(responses:)` returns, so suites can run in
/// parallel without sharing state.
final class ScriptedURLProtocol: URLProtocol, @unchecked Sendable {

    struct Response {
        var status = 200
        var body = Data()
        var contentType = "application/json"

        static func sse(_ body: String) -> Response {
            Response(body: Data(body.utf8), contentType: "text/event-stream")
        }
    }

    /// A request as the stub saw it — `body` is materialised from either `httpBody` or the
    /// body stream `URLSession` substitutes for it.
    struct SeenRequest {
        let request: URLRequest
        let body: Data

        var url: URL? { self.request.url }
        var json: [String: Any]? {
            try? JSONSerialization.jsonObject(with: self.body) as? [String: Any]
        }

        func header(_ name: String) -> String? {
            self.request.value(forHTTPHeaderField: name)
        }
    }

    /// The responses one session serves and the requests it has seen.
    final class Script: @unchecked Sendable {
        fileprivate let id = UUID().uuidString
        private var responses: [Response]
        private var seen: [SeenRequest] = []
        private let lock = NSLock()

        fileprivate init(responses: [Response]) {
            self.responses = responses
        }

        var requests: [SeenRequest] {
            self.lock.withLock { self.seen }
        }

        fileprivate func serve(_ request: SeenRequest) -> Response? {
            self.lock.withLock {
                self.seen.append(request)
                if self.responses.count > 1 { return self.responses.removeFirst() }
                return self.responses.first
            }
        }
    }

    private static let scriptHeader = "X-Scripted-URLProtocol"
    nonisolated(unsafe) private static var scripts: [String: Script] = [:]
    private static let lock = NSLock()

    /// An ephemeral session routed entirely through this stub, and the script it answers from.
    /// An empty `responses` makes every request fail with `.notConnectedToInternet`.
    static func make(responses: [Response]) -> (script: Script, session: URLSession) {
        let script = Script(responses: responses)
        Self.lock.withLock { Self.scripts[script.id] = script }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = [Self.scriptHeader: script.id]
        return (script, URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let script = Self.lock.withLock {
            self.request.value(forHTTPHeaderField: Self.scriptHeader).flatMap { Self.scripts[$0] }
        }
        let seen = SeenRequest(request: self.request, body: Self.materialiseBody(of: self.request))

        guard let response = script?.serve(seen) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": response.contentType]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func materialiseBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
