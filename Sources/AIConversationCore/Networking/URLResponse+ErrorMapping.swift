//
//  URLResponse+ErrorMapping.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

extension URLResponse {
    package func mapError(body: Data = Data()) throws(NetworkError) {
        guard let http = self as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw .http(.unauthorized)
        case 409:
            throw .http(.conflict)
        default:
            if let envelope = Self.decodeEnvelope(body) {
                let params = envelope.error.params ?? []
                if http.statusCode == 422 || !params.isEmpty {
                    throw .http(.validation(
                        status: http.statusCode,
                        message: envelope.error.message,
                        params: params
                    ))
                }
            }
            throw .http(.unhandled(status: http.statusCode))
        }
    }

    private static func decodeEnvelope(_ body: Data) -> ApiErrorEnvelope? {
        guard !body.isEmpty else { return nil }
        return try? JSONDecoder().decode(ApiErrorEnvelope.self, from: body)
    }
}
