//
//  NetworkError.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-22.
//

import Foundation

package enum NetworkError: Error {
    case connection(URLError)
    case encoding(EncodingError)
    case decoding(DecodingError)
    case http(HTTPStatusError)
    case unknown(any Error)

    package enum HTTPStatusError: Error, Equatable {
        case unauthorized
        /// HTTP 409 — e.g. livechat offline on handover, or AI send during an active livechat.
        case conflict
        /// HTTP 422 (or another status) with a decoded `ApiError` envelope and field params.
        case validation(status: Int, message: String, params: [ValidationError])
        case unhandled(status: Int)
    }

    /// Maps an arbitrary error into the closest matching `NetworkError` case.
    /// Pass-through if the error is already a `NetworkError`.
    init(_ error: any Error) {
        switch error {
        case let error as NetworkError: self = error
        case let error as URLError: self = .connection(error)
        case let error as DecodingError: self = .decoding(error)
        case let error as EncodingError: self = .encoding(error)
        default: self = .unknown(error)
        }
    }
}
