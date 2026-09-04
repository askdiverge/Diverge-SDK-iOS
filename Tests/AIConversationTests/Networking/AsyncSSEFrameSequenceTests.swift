//
//  AsyncSSEFrameSequenceTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-10.
//

import Foundation
import Testing
@testable import AIConversationCore

@Suite("AsyncSSEFrameSequence")
struct AsyncSSEFrameSequenceTests {

    @Test("event + data assembles a named frame")
    func namedFrame() async throws {
        let frames = try await assemble("event: status\ndata: {\"x\":1}\n\n")
        #expect(frames == [SSEFrame(name: "status", data: Data(#"{"x":1}"#.utf8))])
    }

    @Test("data without an event line yields a frame with nil name")
    func unnamedFrame() async throws {
        let frames = try await assemble("data: {\"x\":1}\n\n")
        #expect(frames == [SSEFrame(name: nil, data: Data(#"{"x":1}"#.utf8))])
    }

    @Test("multiple frames assemble in order")
    func multipleFrames() async throws {
        let frames = try await assemble(
            "event: status\ndata: a\n\n"
            + "event: part\ndata: b\n\n"
        )
        #expect(frames == [
            SSEFrame(name: "status", data: Data("a".utf8)),
            SSEFrame(name: "part", data: Data("b".utf8))
        ])
    }

    @Test("multiple data lines join with a newline")
    func multiLineData() async throws {
        let frames = try await assemble("event: m\ndata: line1\ndata: line2\n\n")
        #expect(frames == [SSEFrame(name: "m", data: Data("line1\nline2".utf8))])
    }

    @Test("comment lines are ignored")
    func commentsIgnored() async throws {
        let frames = try await assemble(": keep-alive\nevent: status\n: note\ndata: x\n\n")
        #expect(frames == [SSEFrame(name: "status", data: Data("x".utf8))])
    }

    @Test("a blank line with no buffered data is a no-op keep-alive")
    func blankLineKeepAlive() async throws {
        let frames = try await assemble("\n\nevent: status\ndata: x\n\n")
        #expect(frames == [SSEFrame(name: "status", data: Data("x".utf8))])
    }

    @Test("the optional leading space after the field colon is stripped")
    func leadingSpaceStripped() async throws {
        // No space after `data:` / `event:` — value should be preserved verbatim.
        let frames = try await assemble("event:status\ndata:x\n\n")
        #expect(frames == [SSEFrame(name: "status", data: Data("x".utf8))])
    }

    @Test("a trailing frame with no closing blank line is discarded")
    func unterminatedFrameDiscarded() async throws {
        let frames = try await assemble("event: status\ndata: x\n\nevent: part\ndata: y\n")
        #expect(frames == [SSEFrame(name: "status", data: Data("x".utf8))])
    }

    @Test("empty input yields no frames")
    func emptyInput() async throws {
        let frames = try await assemble("")
        #expect(frames.isEmpty)
    }

    @Test("envelope wraps name and data as {\"type\":...,\"data\":...}")
    func envelopeShape() {
        let frame = SSEFrame(name: "status", data: Data(#"{"x":1}"#.utf8))
        #expect(frame.envelope == Data(#"{"type":"status","data":{"x":1}}"#.utf8))
    }

    @Test("envelope emits an empty type when the frame has no name")
    func envelopeNilName() {
        let frame = SSEFrame(name: nil, data: Data(#"{"x":1}"#.utf8))
        #expect(frame.envelope == Data(#"{"type":"","data":{"x":1}}"#.utf8))
    }

    // MARK: - Helper

    private func assemble(_ string: String) async throws -> [SSEFrame] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Data(string.utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        var frames: [SSEFrame] = []
        for try await frame in bytes.sseFrames {
            frames.append(frame)
        }
        return frames
    }
}
