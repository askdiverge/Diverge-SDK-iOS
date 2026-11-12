//
//  LivechatSession+Polling.swift
//  AIConversationEngine
//

import Foundation

struct PollHandles {
    var task: Task<Void, Never>?
    var parked: CheckedContinuation<Void, Never>?
}

extension LivechatSession {

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

    /// Syncs once. `waiting` lets the request wait on the last `sync_cursor`; `confirming` marks
    /// the fresh read that follows a lower `state_version`; `recovering` marks a read for a session
    /// this device wasn't tracking, whose closing messages it hasn't shown.
    func tick(waiting: Bool, confirming: Bool = false, recovering: Bool = false) async {
        let gen = self.generation
        let previous = self.lastStatus
        do {
            // A session this device wasn't tracking numbers its messages from the start.
            let after = previous.isInSession ? self.afterSequence : 0
            let sync = try await self.sync(after: after, waiting: waiting)
            guard gen == self.generation else { return }
            self.consecutiveFailures = 0
            self.syncCursor = sync.syncCursor
            if self.isStale(sync.state) {
                // A replacement session may already have ended, so the fresh read follows whatever
                // its status while this device tracks a session.
                guard previous.isInSession else { return }
                if confirming {
                    // Still lower on a fresh read: a session opened elsewhere replaced this one,
                    // and its log numbers from the start.
                    self.lastStateVersion = nil
                    self.afterSequence = 0
                    self.syncCursor = nil
                    await self.tick(waiting: false)
                } else {
                    // `state_version` counts per session, so a lower one mid-session is either an
                    // older response that arrived late or a replacement session. A fresh read
                    // tells them apart.
                    await self.tick(waiting: false, confirming: true)
                }
                return
            }

            if !previous.isInSession && sync.state.isInSession {
                self.afterSequence = 0
            }
            let closedNow = (previous.isInSession || recovering) && sync.state.status == .closed
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
    /// messages it missed still arrive with history. A 401 ends the visitor session instead.
    func syncAfterClose(after: Int64) async throws(ChatServiceError) -> LivechatSync {
        for _ in 0..<2 {
            do {
                return try await self.sync(after: after, waiting: false)
            } catch .sessionExpired {
                throw .sessionExpired
            } catch {
                continue
            }
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
        let isRestored = !self.hasPublishedState
        self.hasPublishedState = true
        if state.status != .active {
            self.dropTyping()
        }
        self.continuation.yield(
            LivechatSnapshot(
                previousStatus: previous,
                state: state,
                messages: messages,
                sessionExpired: expired,
                generation: self.generation,
                isRestored: isRestored
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

extension LivechatSession {

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
