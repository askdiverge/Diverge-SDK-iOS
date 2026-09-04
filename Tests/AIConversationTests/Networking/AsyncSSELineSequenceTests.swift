//
//  AsyncSSELineSequenceTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation
import Testing
@testable import AIConversationCore

@Suite("AsyncSSELineSequence")
struct AsyncSSELineSequenceTests {

    @Test("LF terminators yield every line including empties")
    func lfTerminators() async throws {
        let lines = try await split("a\nb\n\nc\n")
        #expect(lines == ["a", "b", "", "c"])
    }

    @Test("CRLF terminators yield every line including empties")
    func crlfTerminators() async throws {
        let lines = try await split("a\r\nb\r\n\r\nc\r\n")
        #expect(lines == ["a", "b", "", "c"])
    }

    @Test("CR terminators yield every line including empties")
    func crTerminators() async throws {
        let lines = try await split("a\rb\r\rc\r")
        #expect(lines == ["a", "b", "", "c"])
    }

    @Test("Mixed terminators (LF / CRLF / CR) all split correctly")
    func mixedTerminators() async throws {
        let lines = try await split("a\nb\r\nc\rd\n")
        #expect(lines == ["a", "b", "c", "d"])
    }

    @Test("Stream ending without trailing terminator flushes pending bytes")
    func unterminatedTailIsFlushed() async throws {
        let lines = try await split("abc")
        #expect(lines == ["abc"])
    }

    @Test("Empty input yields no lines")
    func emptyInput() async throws {
        let lines = try await split("")
        #expect(lines.isEmpty)
    }

    // MARK: - Helper

    private func split(_ string: String) async throws -> [String] {
        let bytes = AsyncStream<UInt8> { continuation in
            for byte in Data(string.utf8) {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        var lines: [String] = []
        for try await line in bytes.sseLines {
            lines.append(line)
        }
        return lines
    }
}
