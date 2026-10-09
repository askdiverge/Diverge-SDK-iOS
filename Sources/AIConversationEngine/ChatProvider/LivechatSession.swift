//
//  LivechatSession.swift
//  AIConversationEngine
//

import Foundation
import Synchronization

/// What ``LivechatSession/bootstrap()`` found.
package enum LivechatBootstrapOutcome: Sendable, Equatable {
    /// Queued or talking to an agent; polling has started.
    case inSession
    /// No open session, or its state couldn't be read yet; polling retries the read.
    case notInSession
    /// The visitor session ended (401).
    case sessionExpired
}

/// Polls the visitor's livechat state, and the message log while a session is open, and
/// publishes every change as a ``LivechatSnapshot``.
///
/// Each tick reads `GET /livechat/sync`: the state and every page of messages after the last
/// sequence number published, from one snapshot. When the server returns a `sync_cursor`, the next
/// tick waits on it for up to 20 s, so a change arrives as soon as it happens; otherwise ticks run
/// every 2 s while queued and every 3 s with an agent. Consecutive failures back off exponentially
/// up to 30 s. Polling pauses while the scene is inactive or the chat is off screen, and ticks as
/// soon as both hold again; a wait already in flight finishes first. The session stops
/// polling by itself when a read shows no open session, on a 401, and on ``teardown()``. The poll
/// loop holds the session only while it ticks, so dropping the last reference ends it. It never
/// takes ``ChatProvider``'s busy flag, so polling can't block an AI send.
package actor LivechatSession {

    package typealias SnapshotStream = AsyncStream<LivechatSnapshot>

    nonisolated package let stream: SnapshotStream

    private let service: any ChatServicing
    private let continuation: SnapshotStream.Continuation
    /// Replaces `Task.sleep` in tests.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The poll task and the loop's parked continuation, behind a lock so ``stop()`` and `deinit`
    /// can cancel without hopping onto the actor.
    private let poll = Mutex(PollHandles())

    private var isSceneActive = true
    private var isVisible = true
    private var afterSequence: Int64 = 0
    private var consecutiveFailures = 0
    private var lastStatus: LivechatState.Status = .inactive
    /// The change hint from the last sync; the next tick waits on it.
    private var syncCursor: String?
    /// The state in the last published snapshot; a tick that changes nothing publishes nothing.
    private var lastPublishedState: LivechatState?
    /// Highest `state_version` applied in this generation; older responses are dropped.
    private var lastStateVersion: Int?
    private var sessionExpired = false
    /// Bumped by handover, close and teardown so responses to earlier requests are dropped.
    private var generation: UInt64 = 0

    private static let waitingInterval: Duration = .seconds(2)
    private static let activeInterval: Duration = .seconds(3)
    /// How long a sync may wait for a change, the API's maximum.
    private static let maxWaitMs = 20_000
    /// The pause between waiting syncs, so a server that answers at once can't spin the loop.
    private static let waitGap: Duration = .milliseconds(250)

    private var shouldPoll: Bool {
        self.isSceneActive && self.isVisible && !self.sessionExpired
    }

    package init(
        service: any ChatServicing,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.sleep = sleep
        // Unbounded: a snapshot carries the messages after the cursor, and the cursor has already
        // moved past them, so dropping an undelivered snapshot would lose those messages.
        (self.stream, self.continuation) = SnapshotStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit {
        self.cancelPolling()
        self.continuation.finish()
    }

    /// Cancels the poll loop from any isolation, such as the view model's `deinit`.
    nonisolated package func stop() {
        self.cancelPolling()
    }

    /// Reads the current state once, for example when `/config` says livechat is enabled. An open
    /// session replays its log from the start and starts polling.
    @discardableResult
    package func bootstrap() async -> LivechatBootstrapOutcome {
        self.bumpGeneration()
        let gen = self.generation
        self.sessionExpired = false
        do {
            let sync = try await self.sync(after: 0, waiting: false)
            guard gen == self.generation else { return self.currentOutcome }
            self.consecutiveFailures = 0
            self.syncCursor = sync.syncCursor
            guard sync.state.isInSession else {
                self.publishTransition(to: sync.state, messages: [])
                return .notInSession
            }
            self.afterSequence = 0
            self.publishTransition(to: sync.state, messages: sync.messages)
            self.startPolling()
            return .inSession
        } catch .sessionExpired {
            self.expire(generation: gen)
            return .sessionExpired
        } catch {
            guard gen == self.generation else { return self.currentOutcome }
            // The last known state stands; the poller retries the read with backoff.
            self.startPolling()
            return self.currentOutcome
        }
    }

    /// Queues the visitor for an agent and publishes the status the API returns: `waiting`, or
    /// `active` when it hands back a session that is already open. Polling then reads the state
    /// and messages, retrying a failed read with backoff. A 409 (livechat unavailable) fails with
    /// ``ChatServiceError/conflict``.
    package func handover(
        source: LivechatHandoverRequest.Source,
        partId: String?,
        clientContext: LivechatClientContext? = nil
    ) async throws(ChatServiceError) {
        self.bumpGeneration()
        let gen = self.generation
        self.sessionExpired = false
        do {
            let status = try await self.service.requestLivechatHandover(
                source: source,
                partId: partId,
                clientContext: clientContext
            )
            guard gen == self.generation else { return }
            self.afterSequence = 0
            self.publishTransition(to: LivechatState(status: status), messages: [])
            if status.isInSession {
                self.startPolling(immediate: true)
            }
        } catch .sessionExpired {
            self.expire(generation: gen)
            throw .sessionExpired
        }
    }

    /// Closes the session from the visitor's side, publishes the messages that arrived before
    /// the close, and stops polling.
    package func close(reason: String?) async throws(ChatServiceError) {
        self.bumpGeneration()
        let gen = self.generation
        let wasInSession = self.lastStatus.isInSession
        do {
            try await self.service.closeLivechat(reason: reason)
            let sync = await self.syncAfterClose(after: wasInSession ? self.afterSequence : 0)
            guard gen == self.generation else { return }
            self.publishTransition(to: sync.state, messages: wasInSession ? sync.messages : [])
            self.stopPolling()
        } catch .sessionExpired {
            self.expire(generation: gen)
            throw .sessionExpired
        }
    }

    /// Adopts an active session this device wasn't polling, which a 409 on the AI send reveals.
    /// Publishes `active` at once so the next send can go to the agent, then ticks for the rest.
    package func resumeActive() {
        self.bumpGeneration()
        self.sessionExpired = false
        self.consecutiveFailures = 0
        if !self.lastStatus.isInSession {
            // A session this device wasn't tracking numbers its messages from the start.
            self.afterSequence = 0
            self.publishTransition(to: LivechatState(status: .active), messages: [])
        }
        self.startPolling(immediate: true)
    }

    /// Ticks once now, for example after a livechat send was rejected with 409.
    package func refresh() async {
        await self.tick(waiting: false)
    }

    /// Stops polling, rewinds the cursor and publishes `inactive`. Called on reset and delete.
    package func teardown() {
        self.bumpGeneration()
        self.sessionExpired = false
        self.afterSequence = 0
        self.consecutiveFailures = 0
        self.stopPolling()
        self.publishTransition(to: LivechatState(status: .inactive), messages: [])
    }

    /// Starts or restarts the poll loop. `immediate` ticks before the first wait.
    package func startPolling(immediate: Bool = false) {
        self.cancelPolling()
        self.consecutiveFailures = 0
        let sleep = self.sleep
        self.setPollTask(Task { [weak self] in
            // Re-acquired every iteration, so the sleep between ticks holds no reference.
            var tickNow = immediate
            while !Task.isCancelled {
                if !tickNow {
                    guard let delay = await self?.nextDelay() else { return }
                    do {
                        try await sleep(delay)
                    } catch {
                        return
                    }
                }
                tickNow = false
                guard let session = self, await session.pollOnce() else { return }
            }
        })
    }

    package func stopPolling() {
        self.cancelPolling()
    }

    /// Pauses polling while the app is in the background.
    package func setSceneActive(_ active: Bool) {
        self.isSceneActive = active
        self.resumeIfNeeded()
    }

    /// Pauses polling while the chat view is off screen but the chat is still alive.
    package func setVisible(_ visible: Bool) {
        self.isVisible = visible
        self.resumeIfNeeded()
    }
}

/// A livechat change published by ``LivechatSession``.
///
/// `messages` holds only the messages after the previous snapshot's.
package struct LivechatSnapshot: Sendable, Equatable {
    package let previousStatus: LivechatState.Status
    package let state: LivechatState
    package let messages: [LivechatMessage]
    /// The visitor session ended (401); polling has stopped.
    package let sessionExpired: Bool
}

private struct PollHandles {
    var task: Task<Void, Never>?
    var parked: CheckedContinuation<Void, Never>?
}

private extension LivechatSession {

    var currentOutcome: LivechatBootstrapOutcome {
        self.lastStatus.isInSession ? .inSession : .notInSession
    }

    /// Starts a new generation: later responses to earlier requests are dropped, and a new
    /// session's `state_version` may start low again.
    func bumpGeneration() {
        self.generation += 1
        self.lastStateVersion = nil
        self.syncCursor = nil
    }

    /// Waits until polling may run, then ticks. `false` once the loop should end.
    func pollOnce() async -> Bool {
        await self.waitUntilShouldPoll()
        guard !Task.isCancelled, !self.sessionExpired else { return false }
        await self.tick(waiting: true)
        return !Task.isCancelled && !self.sessionExpired
    }

    func waitUntilShouldPoll() async {
        while !self.shouldPoll, !Task.isCancelled, !self.sessionExpired {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || self.shouldPoll {
                    continuation.resume()
                } else {
                    self.park(continuation)
                }
            }
        }
    }

    func resumeIfNeeded() {
        if self.shouldPoll {
            self.unpark()
        }
    }

    /// Syncs once. `waiting` lets the request wait on the last `sync_cursor`.
    func tick(waiting: Bool) async {
        let gen = self.generation
        let previous = self.lastStatus
        do {
            // A session this device wasn't tracking numbers its messages from the start.
            let after = previous.isInSession ? self.afterSequence : 0
            let sync = try await self.sync(after: after, waiting: waiting)
            guard gen == self.generation else { return }
            self.consecutiveFailures = 0
            self.syncCursor = sync.syncCursor
            if self.isStale(sync.state) { return }

            if !previous.isInSession && sync.state.isInSession {
                self.afterSequence = 0
            }
            let closedNow = previous.isInSession && sync.state.status == .closed
            let messages = sync.state.isInSession || closedNow ? sync.messages : []
            self.publishTransition(to: sync.state, messages: messages, generation: gen)
            if !sync.state.isInSession {
                self.stopPolling()
            }
        } catch .sessionExpired {
            self.expire(generation: gen)
        } catch {
            guard gen == self.generation else { return }
            self.syncCursor = nil
            self.consecutiveFailures += 1
        }
    }

    /// The state and every page of messages after `after`. The first request waits on the last
    /// `sync_cursor` when `waiting` is true. The message cursor moves only when
    /// ``publishTransition(to:messages:expired:generation:)`` publishes the messages.
    func sync(after: Int64, waiting: Bool) async throws(ChatServiceError) -> LivechatSync {
        var messages: [LivechatMessage] = []
        var cursor = after
        var waitOn = waiting ? self.syncCursor : nil
        while true {
            let sync = try await self.service.syncLivechat(
                after: cursor > 0 ? cursor : nil,
                waitMs: waitOn == nil ? nil : Self.maxWaitMs,
                syncCursor: waitOn
            )
            messages += sync.messages
            guard sync.hasMore, let last = sync.messages.last else {
                return LivechatSync(state: sync.state, messages: messages, hasMore: false, syncCursor: sync.syncCursor)
            }
            cursor = last.sequenceNumber
            waitOn = nil
        }
    }

    /// The close already succeeded, so a failed sync retries once. If that fails too, the
    /// session is reported closed with feedback pending, so the visitor can still rate it; the
    /// messages it missed still arrive with history.
    func syncAfterClose(after: Int64) async -> LivechatSync {
        if let sync = try? await self.sync(after: after, waiting: false) {
            return sync
        }
        if let sync = try? await self.sync(after: after, waiting: false) {
            return sync
        }
        return LivechatSync(
            state: LivechatState(status: .closed, feedback: .pending),
            messages: [],
            hasMore: false,
            syncCursor: nil
        )
    }

    func nextDelay() -> Duration {
        guard self.consecutiveFailures > 0 else {
            if self.syncCursor != nil { return Self.waitGap }
            return self.lastStatus == .active ? Self.activeInterval : Self.waitingInterval
        }
        // 2, 4, 8, 16, then 30 s.
        return .seconds(min(30, 1 << min(self.consecutiveFailures, 5)))
    }

    /// Whether `state` is older than one already applied in this generation. A state without a
    /// version always applies.
    func isStale(_ state: LivechatState) -> Bool {
        guard let incoming = state.stateVersion, let last = self.lastStateVersion else { return false }
        return incoming < last
    }

    func publishTransition(
        to state: LivechatState,
        messages: [LivechatMessage],
        expired: Bool = false,
        generation: UInt64? = nil
    ) {
        if let generation, generation != self.generation { return }
        if self.isStale(state) { return }
        if let version = state.stateVersion {
            self.lastStateVersion = version
        }
        if let last = messages.last {
            self.afterSequence = last.sequenceNumber
        }
        if messages.isEmpty, !expired, state == self.lastPublishedState { return }
        self.lastPublishedState = state
        let previous = self.lastStatus
        self.lastStatus = state.status
        self.continuation.yield(
            LivechatSnapshot(
                previousStatus: previous,
                state: state,
                messages: messages,
                sessionExpired: expired
            )
        )
    }

    func expire(generation: UInt64) {
        guard generation == self.generation else { return }
        self.sessionExpired = true
        self.publishTransition(to: LivechatState(status: .inactive), messages: [], expired: true)
        self.stopPolling()
    }
}

private extension LivechatSession {

    nonisolated func setPollTask(_ task: Task<Void, Never>) {
        self.poll.withLock { $0.task = task }
    }

    /// Checks cancellation under the lock ``cancelPolling()`` cancels under, so a cancel can't land
    /// between the loop's last check and the park.
    nonisolated func park(_ continuation: CheckedContinuation<Void, Never>) {
        let toResume = self.poll.withLock { handles -> CheckedContinuation<Void, Never>? in
            if Task.isCancelled { return continuation }
            defer { handles.parked = continuation }
            return handles.parked
        }
        toResume?.resume()
    }

    nonisolated func unpark() {
        let parked = self.poll.withLock { handles in
            defer { handles.parked = nil }
            return handles.parked
        }
        parked?.resume()
    }

    /// Cancels the task and resumes a parked loop so it can't hang.
    nonisolated func cancelPolling() {
        let parked = self.poll.withLock { handles in
            handles.task?.cancel()
            defer { handles = PollHandles() }
            return handles.parked
        }
        parked?.resume()
    }
}
