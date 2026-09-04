//
//  UnknownFallbackTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// Guards the forward-compatibility contract of the hand-written decode logic:
/// any discriminator value the server invents in the future must decode to
/// `.unknown` — never throw. A thrown `DecodingError` propagates out of `postSSE`
/// and terminates the entire SSE stream, so one unrecognised value would
/// otherwise kill a live conversation.
@Suite("Unknown-value fallback — stream survival contract")
struct UnknownFallbackTests {

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    @Test("unrecognised SSE event name decodes to .unknown")
    func unknownEventName() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"some_future_event","data":{"whatever":true}}"#.utf8)
        )
        #expect(event == .unknown)
    }

    @Test("unrecognised delta action decodes to .unknown")
    func unknownDeltaAction() throws {
        let delta = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"some_future_action","block_index":0}"#.utf8)
        )
        #expect(delta == .unknown)
    }

    @Test("unrecognised start_part part_type decodes to .unknown")
    func unknownStartPartType() throws {
        let delta = try self.decoder.decode(
            PartDelta.self,
            from: Data(#"{"action":"start_part","part_type":"some_future_part"}"#.utf8)
        )
        #expect(delta == .unknown)
    }

    @Test("unrecognised part type decodes to .unknown")
    func unknownPartType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"some_future_part","part_id":"p_1"}"#.utf8)
        )
        #expect(part == .unknown)
    }

    @Test("unrecognised part type inside a message does not fail sibling parts")
    func unknownPartAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"some_future_part","part_id":"p_1"},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts.count == 2)
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test("unrecognised rich-text block type decodes to .unknown")
    func unknownBlockType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"rich_text","part_id":"p_1","blocks":[{"type":"some_future_block"}]}"#.utf8)
        )
        #expect(part == .richText(.init(partId: "p_1", blocks: [.unknown])))
    }

    @Test("unrecognised span type decodes to .unknown")
    func unknownSpanType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"rich_text","part_id":"p_1","blocks":[{"type":"paragraph","spans":[{"type":"some_future_span"}]}]}"#.utf8)
        )
        #expect(part == .richText(.init(partId: "p_1", blocks: [.paragraph(.init(spans: [.unknown]))])))
    }

    @Test("unrecognised table cell block type decodes to .unknown")
    func unknownTableCellBlockType() throws {
        let part = try self.decoder.decode(
            Part.self,
            from: Data(#"{"type":"table","part_id":"t_1","headers":[{"blocks":[{"type":"some_future_block"}]}],"rows":[]}"#.utf8)
        )
        #expect(part == .table(.init(
            partId: "t_1",
            caption: nil,
            headers: [.init(blocks: [.unknown])],
            alignments: nil,
            rows: []
        )))
    }

    @Test("unrecognised string-enum values fall back to .unknown")
    func extendableEnumFallback() throws {
        let event = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"status","data":{"status":"some_future_state"}}"#.utf8)
        )
        #expect(event == .status(.init(state: .unknown, message: nil)))
    }
}
