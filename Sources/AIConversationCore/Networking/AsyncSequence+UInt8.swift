//
//  AsyncSequence+UInt8.swift
//  AIConversationCore
//
//  Created by Daniel Wennberg on 2026-06-10.
//

import Foundation

extension AsyncSequence where Element == UInt8 {

    /// Assembles a UTF-8 byte stream into SSE frames per the W3C/WHATWG spec,
    /// layered on `sseLines`.
    /// Consumers receive whole frames, not lines.
    var sseFrames: AsyncSSEFrameSequence<Self> {
        AsyncSSEFrameSequence(base: self)
    }

    /// Splits a UTF-8 byte stream into lines, **preserving empty lines**.
    ///
    /// Use this instead of `URLSession.AsyncBytes.lines` for SSE .
    /// `AsyncLineSequence` collapses empty lines, but empty lines are the SSE
    /// frame boundaries we need to detect. Recognises LF, CR, and CRLF terminators
    /// per the W3C/WHATWG SSE spec.
    var sseLines: AsyncSSELineSequence<Self> {
        AsyncSSELineSequence(base: self)
    }
}
