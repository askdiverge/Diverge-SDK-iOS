//
//  AsyncGate.swift
//  AIConversationTests
//

/// A one-shot latch: `wait()` suspends until `open()`; opening first makes later waits return at
/// once. An actor so the open / wait race (the parked closure usually runs off the main actor)
/// cannot lose a continuation. Shared by the provider, paginator and attachment-encoder tests.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if self.isOpen { return }
        await withCheckedContinuation { self.waiters.append($0) }
    }

    func open() {
        self.isOpen = true
        let waiters = self.waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }
}
