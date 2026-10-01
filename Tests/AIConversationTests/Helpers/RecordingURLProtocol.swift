//
//  RecordingURLProtocol.swift
//  AIConversationTests
//

import Foundation
import Synchronization

/// `URLProtocol` stub that records every request handed to it and replays one scripted response.
///
/// Header and URL assertions need the request as `URLSession` actually sent it — session-level
/// `httpAdditionalHeaders` are merged on the way out, so inspecting the `URLRequest` the caller
/// built would not prove what reached the wire.
///
/// Each ``makeSession(stub:)`` gets its own recording, keyed by an id the session stamps onto
/// every request. Suites therefore need no `.serialized` trait and cannot clobber one another —
/// `URLProtocol` registration is process-wide, but the recordings are not shared.
final class RecordingURLProtocol: URLProtocol {

    /// A scripted HTTP response, delivered as a single chunk.
    struct Stub: Sendable {
        var status = 200
        var body = Data()
        var contentType = "application/json"
    }

    /// Handle to one isolated recording.
    struct Recorder: Sendable {
        fileprivate let id: String

        /// Requests this session has sent, in order.
        var requests: [URLRequest] { RecordingURLProtocol.requests(for: self.id) }
    }

    /// Stamped on every request by the session so the handler can find its own recording.
    static let stubIDHeader = "X-Recording-Stub-Id"

    private struct Recording: Sendable {
        var stub: Stub
        var requests: [URLRequest] = []
    }

    private static let recordings = Mutex<[String: Recording]>([:])

    /// A session that replays `stub` and records into a recorder no other session can see.
    static func makeSession(stub: Stub) -> (URLSession, Recorder) {
        let id = UUID().uuidString
        Self.recordings.withLock { $0[id] = Recording(stub: stub) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = [Self.stubIDHeader: id]

        return (URLSession(configuration: configuration), Recorder(id: id))
    }

    private static func requests(for id: String) -> [URLRequest] {
        Self.recordings.withLock { $0[id]?.requests ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let url = request.url,
            let id = request.value(forHTTPHeaderField: Self.stubIDHeader)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let stub = Self.recordings.withLock { recordings -> Stub? in
            guard var recording = recordings[id] else { return nil }
            recording.requests.append(self.request)
            recordings[id] = recording
            return recording.stub
        }

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.contentType]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {

    /// The value `URLSession` put on the wire for `name`, or `nil` when the header is absent.
    func header(_ name: String) -> String? {
        self.value(forHTTPHeaderField: name)
    }
}
