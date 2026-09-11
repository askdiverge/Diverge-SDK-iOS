//
//  Networking.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

package protocol NetworkService<Failure> {

    associatedtype Failure: Error

    func get<Response: Decodable & Sendable>(
        url: URL,
        headers: [String: String]?
    ) async throws(Failure) -> Response

    /// Raw GET body. Pass `headers` for authenticated endpoints (e.g. GDPR export);
    /// omit them for unauthenticated asset fetches.
    func data(from url: URL, headers: [String: String]?) async throws(Failure) -> Data

    func post<Response: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) async throws(Failure) -> Response

    /// Posts a pre-encoded body. Used when the caller needs a different encoding strategy
    /// than the manager's default encoder (e.g. form actions whose dictionary keys must
    /// stay verbatim).
    func post<Response: Decodable & Sendable>(
        url: URL,
        body: Data,
        headers: [String: String]?
    ) async throws(Failure) -> Response

    /// Posts an encoded payload and expects an empty body (e.g. `POST /rate` returns 200 with
    /// no content). Mirrors ``delete(url:headers:)``.
    func post(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) async throws(Failure)

    /// PATCH with a pre-encoded body (field keys must stay verbatim — see form values).
    func patch<Response: Decodable & Sendable>(
        url: URL,
        body: Data,
        headers: [String: String]?
    ) async throws(Failure) -> Response

    func delete(
        url: URL,
        headers: [String: String]?
    ) async throws(Failure)

    func stream<Event: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
        headers: [String: String]?
    ) -> AsyncThrowingStream<Event, any Error>
}

extension NetworkService {
    /// Unauthenticated raw GET — media and other public assets.
    package func data(from url: URL) async throws(Failure) -> Data {
        try await self.data(from: url, headers: nil)
    }
}
