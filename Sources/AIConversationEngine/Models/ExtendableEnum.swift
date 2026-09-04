//
//  ExtendableEnum.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// A string-backed enum that decodes unknown raw values to a designated `unknown` case
/// instead of throwing. Keeps decoding forward-compatible when the API adds new values —
/// a strict enum failure would otherwise propagate as a `DecodingError` and terminate
/// the whole SSE stream, not just the offending frame.
package protocol ExtendableEnum: RawRepresentable, Decodable where RawValue == String {
    static var unknown: Self { get }
}

extension ExtendableEnum {
    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}
