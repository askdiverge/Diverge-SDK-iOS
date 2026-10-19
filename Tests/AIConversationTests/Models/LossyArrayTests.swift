//
//  LossyArrayTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

/// Pins that one malformed array element is dropped without taking its siblings down.
@Suite("LossyArray — element-wise decoding")
struct LossyArrayTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("malformed elements are dropped and the rest keep their order")
    func dropsMalformedScalars() throws {
        let array = try self.decode(LossyArray<Int>.self, #"[1, "two", 3, null, 4.5, 5]"#)

        #expect(array.elements == [1, 3, 5])
    }

    @Test("a malformed object element is dropped")
    func dropsMalformedObjects() throws {
        let array = try self.decode(
            LossyArray<FormField>.self,
            #"[{"key":"a","label":"A"},{"key":"b"},{"key":"c","label":"C"}]"#
        )

        #expect(array.elements.map(\.key) == ["a", "c"])
    }

    @Test("a value that is not an array fails to decode")
    func nonArrayThrows() {
        #expect(throws: DecodingError.self) {
            try self.decode(LossyArray<Int>.self, "{}")
        }
    }

    // MARK: - Fixtures

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try self.decoder.decode(type, from: Data(json.utf8))
    }
}
