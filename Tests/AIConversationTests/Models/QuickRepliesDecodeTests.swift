//
//  QuickRepliesDecodeTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("QuickReplies — decode")
struct QuickRepliesDecodeTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("decodes quick_replies part")
    func decodesPart() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(
                #"{"type":"quick_replies","part_id":"part_1","replies":["Track order","Return item"]}"#
                    .utf8
            )
        )

        guard case .quickReplies(let quickReplies) = part else {
            Issue.record("Expected quickReplies part")
            return
        }
        #expect(quickReplies.partId == "part_1")
        #expect(quickReplies.replies == ["Track order", "Return item"])
    }

    @Test("empty replies decode to Part.unknown")
    func emptyRepliesUnknown() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"quick_replies","part_id":"part_1","replies":[]}"#.utf8)
        )
        #expect(part == .unknown)
    }
}
