//
//  Recorder.swift
//  AIConversationTests
//

import Synchronization

/// Values a `@Sendable` test closure records while the code under test runs, read back by the
/// test. A `Mutex` guards them, since the closures run off the test's actor.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    var values: [Value] { self.storage.withLock { $0 } }
    var count: Int { self.storage.withLock { $0.count } }

    func record(_ value: Value) {
        self.storage.withLock { $0.append(value) }
    }
}
