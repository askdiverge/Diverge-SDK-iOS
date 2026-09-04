//
//  URLResponse+ErrorMapping.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

extension URLResponse {
    func mapError() throws(NetworkError) {
        guard let http = self as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw .http(.unauthorized)
        default:
            throw .http(.unhandled(status: http.statusCode))
        }
    }
}
