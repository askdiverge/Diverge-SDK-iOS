//
//  JSONDecoder+Wire.swift
//  AIConversationTests
//

import Foundation

extension JSONDecoder {

    /// A decoder configured like the SDK's wire decoders — snake_case keys — for fixture JSON.
    static func wire() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
