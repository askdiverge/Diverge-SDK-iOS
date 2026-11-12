//
//  URLResponse+ErrorMapping.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

extension URLResponse {
    /// Maps an HTTP status onto ``NetworkError/http(_:)``. Any non-2xx status other than 401
    /// carries `body`, so the facade can read the API's error envelope.
    func mapError(body: Data) throws(NetworkError) {
        guard let http = self as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw .http(.unauthorized)
        default:
            throw .http(.unhandled(status: http.statusCode, body: body))
        }
    }
}
