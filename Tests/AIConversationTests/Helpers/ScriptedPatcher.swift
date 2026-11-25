//
//  ScriptedPatcher.swift
//  AIConversationTests
//

import Synchronization
@testable import AIConversation
@testable import AIConversationEngine

/// A ``SessionMetadataQueue`` patcher that fails the calls at the given zero-based indices, waits
/// on `gate` when one is set, and records every patch it accepted. A `Mutex` guards its state,
/// since the queue calls it from its own task.
final class ScriptedPatcher: Sendable {
    private let failures: [Int: ChatServiceError]
    private let gate: AsyncGate?
    private let state = Mutex<(attempts: Int, sent: [SessionMetadataPatchRequest])>((0, []))

    init(failures: [Int: ChatServiceError], gate: AsyncGate?) {
        self.failures = failures
        self.gate = gate
    }

    var attempts: Int { self.state.withLock { $0.attempts } }
    var sent: [SessionMetadataPatchRequest] { self.state.withLock { $0.sent } }

    var patch: SessionMetadataQueue.Patcher {
        { [self] request in
            let index = self.state.withLock { state in
                defer { state.attempts += 1 }
                return state.attempts
            }
            await self.gate?.wait()
            if let failure = self.failures[index] { throw failure }
            self.state.withLock { $0.sent.append(request) }
        }
    }
}
