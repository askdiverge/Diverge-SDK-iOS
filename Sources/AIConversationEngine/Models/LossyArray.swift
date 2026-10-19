//
//  LossyArray.swift
//  AIConversationEngine
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// Decodes a JSON array element by element, dropping the ones that fail instead of failing
/// the whole array. Used where one malformed entry must not take its siblings down — the same
/// posture ``Part`` takes with `.unknown`, for arrays whose element type has no such case.
package struct LossyArray<Element: Decodable>: Decodable {

    package let elements: [Element]

    package init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else if container.currentIndex == index {
                // A failed decode leaves the cursor in place — consume the bad element so the
                // loop advances; `Skip` accepts any JSON value.
                _ = try? container.decode(Skip.self)
                if container.currentIndex == index { break }
            }
        }
        self.elements = elements
    }

    /// Matches any JSON value without keeping it.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
