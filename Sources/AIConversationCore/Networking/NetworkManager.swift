//
//  NetworkManager.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-20.
//

import Foundation

package final class NetworkManager: NetworkService, Sendable {

    package typealias Failure = NetworkError

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let session: URLSession

    package init(
        decoder: JSONDecoder,
        encoder: JSONEncoder,
        session: URLSession
    ) {
        self.decoder = decoder
        self.encoder = encoder
        self.session = session
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    package func get<Response: Decodable & Sendable>(
        url: URL,
        headers: [String: String]?
    ) async throws(NetworkError) -> Response {
        let request = URLRequest(url: url, method: .get, headers: headers)
        return try await self.send(request)
    }

    package func data(from url: URL) async throws(NetworkError) -> Data {
        try await self.mappingErrors {
            let request = URLRequest(url: url, method: .get, headers: nil)
            let (data, response) = try await self.session.data(for: request)
            try response.mapError()
            return data
        }
    }

    package func post<Response: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) async throws(NetworkError) -> Response {
        let request = try self.makeRequest(
            url: url,
            method: .post,
            payload: payload,
            headers: headers
        )

        return try await self.send(request)
    }

    package func delete(
        url: URL,
        headers: [String: String]?
    ) async throws(NetworkError) {
        let request = URLRequest(url: url, method: .delete, headers: headers)
        try await self.sendVoid(request)
    }

    package func stream<Event: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) -> AsyncThrowingStream<Event, any Error> {
        let (stream, continuation) = AsyncThrowingStream<Event, any Error>.makeStream()

        let task = Task {
            do {
                try await self.postSSE(
                    url: url,
                    payload: payload,
                    headers: headers
                ) { event in
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }

        return stream
    }
}

private extension NetworkManager {

    func mappingErrors<T: Sendable>(
        body: () async throws -> T
    ) async throws(NetworkError) -> T {
        do {
            return try await body()
        } catch {
            throw NetworkError(error)
        }
    }

    func send<Response: Decodable & Sendable>(
        _ request: URLRequest
    ) async throws(NetworkError) -> Response {
        try await self.mappingErrors {
            let (data, response) = try await self.session.data(for: request)
            try response.mapError()
            return try self.decoder.decode(Response.self, from: data)
        }
    }

    func sendVoid(_ request: URLRequest) async throws(NetworkError) {
        try await self.mappingErrors {
            let (_, response) = try await self.session.data(for: request)
            try response.mapError()
        }
    }

    func makeRequest(
        url: URL,
        method: URLRequest.EndpointMethod,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) throws(NetworkError) -> URLRequest {
        var request = URLRequest(url: url, method: method, headers: headers)
        do {
            request.httpBody = try self.encoder.encode(payload)
        } catch {
            throw NetworkError(error)
        }
        return request
    }

    func postSSE<Event: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?,
        yield: (Event) -> Void
    ) async throws(NetworkError) {
        try await self.mappingErrors {

            let request = try self.makeRequest(
                url: url,
                method: .post,
                payload: payload,
                headers: headers
            )

            let (bytes, response) = try await self.session.bytes(for: request)
            try response.mapError()

            for try await frame in bytes.sseFrames {
                yield(try self.decoder.decode(Event.self, from: frame.envelope))
            }
        }
    }
}
