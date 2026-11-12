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
/// any discriminator value the server invents in the future, and any part or delta
/// whose payload it reshapes, must decode to `.unknown` — never throw. A thrown
/// `DecodingError` propagates out of `postSSE` and terminates the entire SSE stream,
/// so one unrecognised value would otherwise kill a live conversation.
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

    @Test("a malformed form marker decodes to .unknown and does not fail siblings")
    func malformedFormMarkerIsUnknown() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"show_contact_form"},
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts[0] == .unknown)
        #expect(message.parts[1] != .unknown)
    }

    @Test(
        "a malformed rich text, table or products part decodes to .unknown",
        arguments: [
            #"{"type":"rich_text","part_id":"p_1"}"#,
            #"{"type":"rich_text","part_id":"p_1","blocks":[{"type":"paragraph"}]}"#,
            #"{"type":"table","part_id":"t_1","columns":[{"header":"Size"}]}"#,
            #"{"type":"products","part_id":"pr_1","products":[{"id":"sku_1","title":"Shirt"}]}"#
        ]
    )
    func malformedPartIsUnknown(json: String) throws {
        let part = try self.decoder.decode(Part.self, from: Data(json.utf8))
        #expect(part == .unknown)
    }

    @Test("a malformed part, or one that isn't an object, does not fail its message")
    func malformedPartAmongSiblings() throws {
        let message = try self.decoder.decode(
            Message.self,
            from: Data("""
                {"message_id":"m_1","role":"assistant","parts":[
                    {"type":"table","part_id":"t_1","columns":[{"header":"Size"}]},
                    "not a part",
                    {"type":"rich_text","part_id":"p_2","blocks":[]}
                ],"created_at":"2026-01-01T00:00:00Z"}
                """.utf8)
        )
        #expect(message.parts == [.unknown, .unknown, .richText(.init(partId: "p_2", blocks: []))])
    }

    @Test(
        "a delta whose payload doesn't decode is .unknown",
        arguments: [
            #"{"action":"start_part","part_type":"table","columns":[{"header":"Size"}]}"#,
            #"{"action":"start_block","block_type":"paragraph"}"#,
            #"{"action":"append_text","block_index":0}"#,
            #"{"action":"append_span","block_index":0,"span":{"type":"link","text":"Size guide"}}"#,
            #"{"action":"append_item","block_index":0,"item":{}}"#,
            #"{"action":"append_product","product":{"id":"sku_1","title":"Shirt"}}"#,
            #"{"action":"append_row","row":"not a row"}"#,
            #"{"action":"end_block"}"#
        ]
    )
    func malformedDeltaIsUnknown(json: String) throws {
        let delta = try self.decoder.decode(PartDelta.self, from: Data(json.utf8))
        #expect(delta == .unknown)
    }

    @Test("a stream event carrying a malformed part or delta still decodes")
    func malformedPartEvents() throws {
        let part = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"part","data":{"part":{"type":"table","part_id":"t_1","columns":[]}}}"#.utf8)
        )
        let delta = try self.decoder.decode(
            StreamEvent.self,
            from: Data(#"{"type":"part_delta","data":{"part_id":"t_1","delta":{"action":"append_row","row":"not a row"}}}"#.utf8)
        )

        #expect(part == .part(.unknown))
        #expect(delta == .delta(partId: "t_1", .unknown))
    }

    @Test(
        "a part_delta without its part_id or delta decodes to .unknown",
        arguments: [
            #"{"type":"part_delta","data":{"delta":{"action":"end_part"}}}"#,
            #"{"type":"part_delta","data":{"part_id":"t_1"}}"#
        ]
    )
    func partDeltaWithoutTargetIsUnknown(json: String) throws {
        let event = try self.decoder.decode(StreamEvent.self, from: Data(json.utf8))
        #expect(event == .unknown)
    }
}
