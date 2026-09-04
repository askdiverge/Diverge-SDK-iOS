//
//  AsyncSSELineSequence.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

struct AsyncSSELineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {

    typealias Element = String

    let base: Base

    func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator())
    }

    struct Iterator: AsyncIteratorProtocol {

        private var base: Base.AsyncIterator
        private var buffer: [UInt8] = []
        private var sawCR = false
        private var finished = false

        init(base: Base.AsyncIterator) {
            self.base = base
        }

        mutating func next() async throws -> String? {
            guard !finished else { return nil }
            while let byte = try await base.next() {
                switch byte {
                case 0x0D: // CR - Carriage Return, 'Swift' \r
                    sawCR = true
                    return drain()
                case 0x0A: // LF - Line Feed, 'Swift' \n

                    // CRLF — already emitted on CR
                    if sawCR {
                        sawCR = false
                        continue
                    }

                    return drain()
                default:
                    sawCR = false
                    buffer.append(byte)
                }
            }

            finished = true
            return buffer.isEmpty ? nil : drain()
        }

        private mutating func drain() -> String {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll(keepingCapacity: true)
            return line
        }
    }
}
