//
//  AsyncSSEFrameSequence.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-06-08.
//

import Foundation

/// A dispatched SSE frame — the event name (if any) and its accumulated `data:`
/// payload.
struct SSEFrame: Sendable, Equatable {

    let name: String?
    let data: Data

    /// The frame as a `{"type": <name>, "data": <payload>}` JSON envelope, so a
    /// single `Decodable` can discriminate on the event name. Consumers decoding
    /// a discriminated event type decode from this rather than `data` directly.
    ///
    /// `type`/`data` are the wrapper keys the decoded type must match. The frame
    /// never knows the event-name *values* — generic SSE-to-discriminated-decode
    /// infrastructure, not specific to any one API.
    var envelope: Data {
        var envelope = Data()
        envelope.append(contentsOf: #"{"type":""#.utf8)
        envelope.append(contentsOf: (self.name ?? "").utf8)
        envelope.append(contentsOf: #"","data":"#.utf8)
        envelope.append(self.data)
        envelope.append(contentsOf: "}".utf8)
        return envelope
    }
}

/// SSE field prefixes per the W3C/WHATWG spec.
private enum Field {
    static let comment: String = ":"
    static let event: String = "event:"
    static let data: String = "data:"
}

struct AsyncSSEFrameSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {

    typealias Element = SSEFrame

    let base: Base

    func makeAsyncIterator() -> Iterator {
        Iterator(lines: self.base.sseLines.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {

        private var lines: AsyncSSELineSequence<Base>.Iterator
        private var buffer = ""
        private var pendingName: String?

        init(lines: AsyncSSELineSequence<Base>.Iterator) {
            self.lines = lines
        }

        /// Pulls lines until an empty line closes a frame, or the stream ends.
        /// Per-line handling per spec:
        /// - **empty line** — frame boundary: emit `(pendingName, buffer)`, reset.
        ///   Empty buffer -> keep-alive, skip.
        /// - **`:` prefix** — comment, skip.
        /// - **`event:`** — capture the event name for the frame being built.
        /// - **`data:`** — strip one optional leading space, append with `\n` (multi-line data joining).
        ///
        /// A trailing frame with no closing empty line at EOF is discarded per spec.
        mutating func next() async throws -> SSEFrame? {
            while let line = try await self.lines.next() {
                if line.isEmpty {
                    guard !self.buffer.isEmpty else { continue }
                    let frame = SSEFrame(
                        name: self.pendingName,
                        data: Data(self.buffer.dropLast().utf8)
                    )
                    self.buffer = ""
                    self.pendingName = nil
                    return frame

                } else if line.hasPrefix(Field.comment) {
                    continue

                } else if line.hasPrefix(Field.event) {
                    self.pendingName = Self.value(of: line, after: Field.event)

                } else if line.hasPrefix(Field.data) {
                    self.buffer += Self.value(of: line, after: Field.data) + "\n"
                }
            }
            return nil
        }

        /// The value of a `field:` line — the text after `prefix`, with one
        /// optional leading space stripped per spec.
        private static func value(of line: String, after prefix: String) -> String {
            let value = line.dropFirst(prefix.count)
            return String(value.hasPrefix(" ") ? value.dropFirst() : value)
        }
    }
}
