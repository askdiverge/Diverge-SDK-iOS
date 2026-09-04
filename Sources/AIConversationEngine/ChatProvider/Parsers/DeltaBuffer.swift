//
//  DeltaBuffer.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-11.
//

/// Accumulates the in-flight part's deltas and renders the current preview. Holds raw
/// `PartDelta`s and stays type-agnostic — the injected `parse` body dispatches on the
/// part type, so one buffer serves every type. The provider `reset`s it at the authoritative `part`
struct DeltaBuffer {

    private let parse: @Sendable ([PartDelta]) -> ChatResponse?
    private var deltas: [PartDelta] = []

    /// Parts finalized so far — also the index of the part currently streaming, i.e.
    /// where its bubble sits in the turn.
    private(set) var commitCount = 0

    init(parse: @escaping @Sendable ([PartDelta]) -> ChatResponse?) {
        self.parse = parse
    }

    mutating func append(_ delta: PartDelta) {
        self.deltas.append(delta)
    }

    func render() -> ChatResponse? {
        self.parse(self.deltas)
    }

    /// Finalize the streaming part and advance to the next.
    mutating func commit() {
        self.deltas = []
        self.commitCount += 1
    }

    /// Discard the streaming part without counting it — for parts that render nothing
    /// (unsupported types), so its bubble index isn't consumed.
    mutating func reset() {
        self.deltas = []
    }
}
