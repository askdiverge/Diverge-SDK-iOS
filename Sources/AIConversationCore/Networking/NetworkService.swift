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

    func data(from url: URL) async throws(Failure) -> Data

    func post<Response: Decodable & Sendable>(
        url: URL,
        payload: some Encodable & Sendable,
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
