//
//  LivechatSession.swift
//  AIConversationEngine
//

import Foundation

/// Outcome of ``LivechatSession/bootstrap()`` so form `start_livechat` can notice a failed
/// queue without racing the snapshot stream (and without POSTing handover).
package enum LivechatBootstrapOutcome: Sendable, Equatable {
    case inSession
    case notInSession
    case sessionExpired
}

/// Polls livechat state (and messages while queued/active) and publishes snapshots.
///
/// One loop covers both endpoints. Cadence is 2 s while waiting and 3 s while active; consecutive
/// failures back off exponentially up to 30 s. Scene-phase **and** on-screen gating pause the
/// loop; a catch-up tick fires when both become true again. The actor owns stop conditions
/// (left session, 401, `teardown`, owner `stop`) so the view model never has to guess.
/// Never touches ``ChatProvider``'s send busy flag — polling must not fight an in-flight AI send.
package actor LivechatSession {

    package typealias SnapshotStream = AsyncStream<LivechatSnapshot>

    nonisolated package let stream: SnapshotStream

    private let service: any ChatServicing
    private let continuation: SnapshotStream.Continuation
    /// Test seam — replaces `Task.sleep`. Production uses real wall-clock sleeps.
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Holds the poll `Task` and park continuation so `stop()` can cancel from `deinit` /
    /// a nonisolated context without waiting on the actor.
    private let pollBox = PollTaskBox()

    private var isSceneActive = true
    private var isVisible = true
    private var afterSequence: Int64 = 0
    private var consecutiveFailures = 0
    private var lastStatus: LivechatState.Status = .inactive
    private var lastState = LivechatState(status: .inactive)
    /// Highest `state_version` applied this generation — drops stale in-flight GETs.
    private var lastStateVersion: Int?
    private var sessionExpired = false
    /// Bumped on handover / close / teardown / expire so in-flight ticks are dropped.
    private var generation: UInt64 = 0

    private static let waitingInterval: Duration = .seconds(2)
    private static let activeInterval: Duration = .seconds(3)

    private var shouldPoll: Bool {
        self.isSceneActive && self.isVisible && !self.sessionExpired
    }

    /// Bumps generation and clears the version watermark for a new session epoch.
    private func bumpGeneration() {
        self.generation += 1
        self.lastStateVersion = nil
    }

    package init(
        service: any ChatServicing,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.sleep = sleep
        // Unbounded: snapshots carry incremental messages; latest-wins would drop a tick
        // the main actor has not drained yet and the cursor has already advanced past it.
        let pair = SnapshotStream.makeStream(bufferingPolicy: .unbounded)
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    deinit {
        self.pollBox.cancel()
        self.continuation.finish()
    }

    /// Cancels the poll loop from any isolation (view-model `deinit`, teardown).
    nonisolated package func stop() {
        self.pollBox.cancel()
    }

    /// One-shot rehydration when `/config` says livechat is enabled. A waiting/active result
    /// replays the log from sequence 0 and starts polling (first loop tick after the cadence
    /// sleep — the bootstrap fetch already published).
    @discardableResult
    package func bootstrap() async -> LivechatBootstrapOutcome {
        self.bumpGeneration()
        let gen = self.generation
        do {
            let state = try await self.service.fetchLivechatState()
            guard gen == self.generation else {
                return self.lastStatus.isInSession ? .inSession : .notInSession
            }
            self.consecutiveFailures = 0
            if self.isStaleState(state) {
                return self.lastStatus.isInSession ? .inSession : .notInSession
            }
            if state.isInSession {
                self.afterSequence = 0
                let messages = try await self.fetchMessagesPage()
                guard gen == self.generation else {
                    return self.lastStatus.isInSession ? .inSession : .notInSession
                }
                self.publishTransition(to: state, messages: messages)
                self.startPolling(immediate: false)
                return .inSession
            } else {
                self.publishTransition(to: state, messages: [])
                return .notInSession
            }
        } catch ChatServiceError.sessionExpired {
            self.expire(generation: gen)
            return .sessionExpired
        } catch {
            guard gen == self.generation else {
                return self.lastStatus.isInSession ? .inSession : .notInSession
            }
            self.publishTransition(to: LivechatState(status: .inactive), messages: [])
            return .notInSession
        }
    }

    /// Visitor requested a human. Uses the subsequent `GET /state` as the source of truth
    /// (handover 200 may reuse an already-`active` session). Starts polling after publishing.
    package func handover(
        source: String,
        partId: String?,
        clientContext: LivechatClientContext? = nil
    ) async throws(ChatServiceError) {
        self.bumpGeneration()
        let gen = self.generation
        self.sessionExpired = false
        do {
            try await self.service.requestLivechatHandover(
                source: source,
                partId: partId,
                clientContext: clientContext
            )
            self.afterSequence = 0
            self.consecutiveFailures = 0
            let state = try await self.service.fetchLivechatState()
            guard gen == self.generation else { return }
            if self.isStaleState(state) { return }
            let messages = state.isInSession ? try await self.fetchMessagesPage() : []
            guard gen == self.generation else { return }
            self.publishTransition(to: state, messages: messages)
            if state.isInSession {
                self.startPolling(immediate: false)
            }
        } catch ChatServiceError.sessionExpired {
            self.expire(generation: gen)
            throw ChatServiceError.sessionExpired
        } catch {
            throw error
        }
    }

    /// Visitor left the queue / ended the chat. Fetches remaining messages on the closed
    /// edge, publishes, then stops.
    package func close(reason: String?) async throws(ChatServiceError) {
        self.bumpGeneration()
        let gen = self.generation
        let wasInSession = self.lastStatus.isInSession
        do {
            try await self.service.closeLivechat(reason: reason)
            var messages: [LivechatMessage] = []
            if wasInSession {
                messages = (try? await self.fetchMessagesPage()) ?? []
            }
            let state = await self.fetchStateAfterSuccessfulClose()
            guard gen == self.generation else { return }
            self.publishTransition(to: state, messages: messages)
            self.stopPolling()
        } catch ChatServiceError.sessionExpired {
            self.expire(generation: gen)
            throw ChatServiceError.sessionExpired
        } catch {
            throw error
        }
    }

    /// A 409 on the AI send revealed an active session this device was not polling.
    /// Optimistic `active` so the re-route can send, then an immediate tick for the agent.
    package func resumeActive() {
        self.bumpGeneration()
        self.sessionExpired = false
        self.consecutiveFailures = 0
        if !self.lastStatus.isInSession {
            self.publishTransition(to: LivechatState(status: .active), messages: [])
        }
        self.startPolling(immediate: true)
    }

    /// One tick now (livechat-send 409: session may have closed between polls).
    package func refresh() async {
        await self.tick()
    }

    /// Stops polling, resets the cursor and mirrored status. Called from reset / delete.
    package func teardown() {
        self.bumpGeneration()
        self.sessionExpired = false
        self.afterSequence = 0
        self.consecutiveFailures = 0
        self.stopPolling()
        self.publishTransition(to: LivechatState(status: .inactive), messages: [])
    }

    /// Starts (or restarts) the poll loop. `immediate` ticks before the first cadence sleep.
    package func startPolling(immediate: Bool = false) {
        self.pollBox.cancel()
        self.consecutiveFailures = 0
        self.pollBox.replace(Task { [weak self] in
            await self?.runLoop(immediate: immediate)
        })
    }

    /// Stops the poll loop (visitor left, session closed, reset).
    package func stopPolling() {
        self.pollBox.cancel()
    }

    /// Scene-phase gate — suspend while backgrounded; catch up immediately on return.
    package func setSceneActive(_ active: Bool) {
        self.isSceneActive = active
        self.resumeIfNeeded()
    }

    /// On-screen gate — suspend while `ChatView` is not in the hierarchy (sheet dismissed
    /// but `AIChat` still alive). Combined with ``setSceneActive(_:)``.
    package func setVisible(_ visible: Bool) {
        self.isVisible = visible
        self.resumeIfNeeded()
    }

    /// Scene-phase gate (back-compat name used by the view).
    package func setActive(_ active: Bool) {
        self.setSceneActive(active)
    }

    /// Resets the message cursor (e.g. after a fresh handover).
    package func resetCursor() {
        self.afterSequence = 0
    }
}

/// Livechat observation published by ``LivechatSession``.
///
/// `messages` are incremental (ids already seen are dropped by ``ChatProvider/appendLivechat``).
/// The stream is unbounded so a slow consumer cannot lose a tick.
package struct LivechatSnapshot: Sendable, Equatable {
    package let previousStatus: LivechatState.Status
    package let state: LivechatState
    /// New messages since the previous tick (empty when only state changed).
    package let messages: [LivechatMessage]
    package let sessionExpired: Bool

    package init(
        previousStatus: LivechatState.Status = .inactive,
        state: LivechatState,
        messages: [LivechatMessage] = [],
        sessionExpired: Bool = false
    ) {
        self.previousStatus = previousStatus
        self.state = state
        self.messages = messages
        self.sessionExpired = sessionExpired
    }
}

extension LivechatState.Status {
    /// Queued or talking to an agent — still needs polling.
    package var isInSession: Bool {
        self == .waiting || self == .active
    }
}

private extension LivechatSession {

    func runLoop(immediate: Bool) async {
        if immediate {
            await self.waitUntilShouldPoll()
            guard !Task.isCancelled, !self.sessionExpired else { return }
            await self.tick()
        }
        while !Task.isCancelled {
            if self.sessionExpired { return }
            do {
                try await self.sleep(self.nextDelay())
            } catch {
                return
            }
            await self.waitUntilShouldPoll()
            guard !Task.isCancelled, !self.sessionExpired else { return }
            await self.tick()
        }
    }

    func waitUntilShouldPoll() async {
        while !self.shouldPoll && !Task.isCancelled && !self.sessionExpired {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || self.shouldPoll {
                    cont.resume()
                    return
                }
                self.pollBox.setResume(cont)
            }
        }
    }

    func resumeIfNeeded() {
        if self.shouldPoll {
            self.pollBox.resumeWait()
        }
    }

    func tick() async {
        let gen = self.generation
        do {
            let state = try await self.service.fetchLivechatState()
            guard gen == self.generation else { return }
            self.consecutiveFailures = 0
            // Drop stale in-flight GETs before /messages so a discarded tick cannot
            // advance `afterSequence` and skip agent lines the UI never sees.
            if self.isStaleState(state) { return }

            let previous = self.lastStatus
            let closedEdge = previous.isInSession && state.status == .closed
            var messages: [LivechatMessage] = []
            if state.isInSession || closedEdge {
                // Limit 100 (contract max). `has_more` is ignored — a single tick catching
                // more than 100 new rows is not a livechat-scale event; the next tick continues.
                messages = try await self.fetchMessagesPage()
                guard gen == self.generation else { return }
            }

            self.publishTransition(to: state, messages: messages, generation: gen)
            if previous.isInSession && !state.isInSession {
                self.stopPolling()
            }
        } catch ChatServiceError.sessionExpired {
            self.expire(generation: gen)
        } catch {
            guard gen == self.generation else { return }
            self.consecutiveFailures += 1
        }
    }

    /// Close HTTP already succeeded. Retry GET once; if both fail, publish closed + pending
    /// so CSAT can still be offered rather than inventing `not_available`.
    func fetchStateAfterSuccessfulClose() async -> LivechatState {
        if let state = try? await self.service.fetchLivechatState() {
            return state
        }
        if let state = try? await self.service.fetchLivechatState() {
            return state
        }
        return LivechatState(
            status: .closed,
            feedback: LivechatState.Feedback(status: .pending)
        )
    }

    func fetchMessagesPage() async throws(ChatServiceError) -> [LivechatMessage] {
        let after: Int64? = self.afterSequence > 0 ? self.afterSequence : nil
        let page = try await self.service.fetchLivechatMessages(after: after)
        if let last = page.messages.last {
            self.afterSequence = last.sequenceNumber
        }
        return page.messages
    }

    func nextDelay() -> Duration {
        if self.consecutiveFailures == 0 {
            return self.lastStatus == .active ? Self.activeInterval : Self.waitingInterval
        }
        // Exponential backoff: 2, 4, 8, … capped at 30 s.
        let seconds = min(30.0, pow(2.0, Double(self.consecutiveFailures)))
        return .seconds(seconds)
    }

    /// Incoming `/state` is older than the last applied version this generation.
    /// Missing versions always apply (older stand-ins / servers).
    func isStaleState(_ state: LivechatState) -> Bool {
        guard let incoming = state.stateVersion, let last = self.lastStateVersion else {
            return false
        }
        return incoming < last
    }

    func publishTransition(
        to state: LivechatState,
        messages: [LivechatMessage],
        expired: Bool = false,
        generation: UInt64? = nil
    ) {
        if let generation, generation != self.generation { return }
        // Backstop — `tick` / bootstrap / handover already skip stale GETs before /messages.
        if self.isStaleState(state) { return }
        if let incoming = state.stateVersion {
            self.lastStateVersion = incoming
        }
        let previous = self.lastStatus
        self.lastStatus = state.status
        self.lastState = state
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
        self.publishTransition(
            to: LivechatState(status: .inactive),
            messages: [],
            expired: true
        )
        self.stopPolling()
    }
}

/// Lock-protected poll task + park continuation. `cancel()` is safe from `deinit` and
/// `nonisolated stop()` — it resumes any waiter so the loop cannot hang, then cancels the task.
private final class PollTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?

    func replace(_ task: Task<Void, Never>?) {
        self.lock.lock()
        let previous = self.task
        self.task = task
        self.lock.unlock()
        previous?.cancel()
    }

    func setResume(_ cont: CheckedContinuation<Void, Never>) {
        self.lock.lock()
        let previous = self.resume
        self.resume = cont
        self.lock.unlock()
        previous?.resume()
    }

    func resumeWait() {
        self.lock.lock()
        let cont = self.resume
        self.resume = nil
        self.lock.unlock()
        cont?.resume()
    }

    func cancel() {
        self.lock.lock()
        let task = self.task
        self.task = nil
        let cont = self.resume
        self.resume = nil
        self.lock.unlock()
        cont?.resume()
        task?.cancel()
    }
}
