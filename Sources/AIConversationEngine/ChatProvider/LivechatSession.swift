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
/// polling by itself when a read shows no open session, on a 401, and on ``teardown()``. A loop
/// parked while polling is paused holds the session, so its owner calls ``stop()`` when it goes
/// away. It never takes ``ChatProvider``'s busy flag, so polling can't block an AI send.
package actor LivechatSession {

    package typealias SnapshotStream = AsyncStream<LivechatSnapshot>

    nonisolated package let stream: SnapshotStream

    let service: any ChatServicing
    let continuation: SnapshotStream.Continuation
    /// Replaces `Task.sleep` in tests.
    let sleep: @Sendable (Duration) async throws -> Void

    /// The poll task and the loop's parked continuation, behind a lock so ``stop()`` and `deinit`
    /// can cancel without hopping onto the actor.
    let poll = Mutex(PollHandles())

    private var isSceneActive = true
    private var isVisible = true
    var afterSequence: Int64 = 0
    var consecutiveFailures = 0
    var lastStatus: LivechatState.Status = .inactive
    /// The change hint from the last sync; the next tick waits on it.
    var syncCursor: String?
    /// The state in the last published snapshot; a tick that changes nothing publishes nothing.
    var lastPublishedState: LivechatState?
    /// Highest `state_version` applied in this generation; older responses are dropped.
    var lastStateVersion: Int?
    var sessionExpired = false
    /// Bumped by handover, close and teardown so responses to earlier requests are dropped.
    var generation: UInt64 = 0
    /// Set once a state is published. Until then a published state is one the session found
    /// already in place, which its snapshot marks as restored.
    var hasPublishedState = false
    /// How long the visitor's draft may sit unchanged before the agent is told typing stopped.
    private let typingIdle: Duration
    /// The typing state the agent should see.
    var wantsTyping = false
    /// The typing state the agent was last told by a post that succeeded.
    var isTypingSent = false
    /// Ends the typing burst after ``typingIdle`` without a draft change.
    var typingIdleTask: Task<Void, Never>?
    /// Sends ``wantsTyping`` until the agent has it; one at a time, so posts arrive in order.
    var typingPost: Task<Void, Never>?
    /// Bumped when the typing state is dropped, so a post in flight doesn't record its result.
    var typingEpoch = 0

    static let waitingInterval: Duration = .seconds(2)
    static let activeInterval: Duration = .seconds(3)
    /// How long a sync may wait for a change, the API's maximum.
    static let maxWaitMs = 20_000
    /// The pause between waiting syncs, so a server that answers at once can't spin the loop.
    static let waitGap: Duration = .milliseconds(250)
    /// Attempts per typing change before it waits for the next one.
    static let typingAttempts = 3
    /// The pause before a failed typing post is tried again.
    static let typingRetry: Duration = .seconds(1)

    var shouldPoll: Bool {
        self.isSceneActive && self.isVisible && !self.sessionExpired
    }

    package init(
        service: any ChatServicing,
        typingIdle: Duration = .milliseconds(1500),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.typingIdle = typingIdle
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
                // A session that closed before this read still carries its log, and its last
                // messages may be newer than history; the provider skips what history shows.
                self.publishTransition(to: sync.state, messages: sync.state.status == .closed ? sync.messages : [])
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
            // The handover is a change this device made, seen as it happens.
            self.hasPublishedState = true
            self.publishTransition(to: LivechatState(status: status), messages: [])
            if status.isInSession {
                self.startPolling(immediate: true)
            }
        } catch .sessionExpired {
            self.expire(generation: gen)
            throw .sessionExpired
        } catch .conflict {
            throw .conflict
        } catch {
            // The server may have opened the session even though its response was lost; polling
            // finds it, and stops by itself when there is none.
            if gen == self.generation {
                self.startPolling(immediate: true)
            }
            throw error
        }
    }

    /// Closes the session from the visitor's side, publishes the messages that arrived before
    /// the close, and stops polling. A 409 (no open session) fails with ``ChatServiceError/conflict``.
    package func close(reason: String?) async throws(ChatServiceError) {
        self.bumpGeneration()
        let gen = self.generation
        let wasInSession = self.lastStatus.isInSession
        do {
            try await self.service.closeLivechat(reason: reason)
            let sync = try await self.syncAfterClose(after: wasInSession ? self.afterSequence : 0)
            guard gen == self.generation else { return }
            self.publishTransition(to: sync.state, messages: wasInSession ? sync.messages : [])
            self.stopPolling()
        } catch .sessionExpired {
            self.expire(generation: gen)
            throw .sessionExpired
        }
    }

    /// Reads the state after a 409 on the AI send, which a session this device wasn't polling
    /// causes, and returns whether an agent session is active. An open session is published with
    /// its messages and polled from then on, and so is one that closed meanwhile with its last
    /// messages. A read that fails leaves the poller retrying it.
    package func resumeActive() async -> Bool {
        self.bumpGeneration()
        self.sessionExpired = false
        self.consecutiveFailures = 0
        await self.tick(waiting: false, recovering: true)
        guard self.lastStatus.isInSession || self.consecutiveFailures > 0 else { return false }
        self.startPolling()
        return self.lastStatus == .active
    }

    /// Ticks once now, for example after a livechat send was rejected with 409.
    package func refresh() async {
        await self.tick(waiting: false)
    }

    /// The visitor's draft changed. While an agent is connected, the agent is told the visitor is
    /// typing once per burst, and that they stopped after ``typingIdle`` without a change or when
    /// the draft empties.
    package func visitorTyping(isEmpty: Bool) {
        self.typingIdleTask?.cancel()
        guard self.lastStatus == .active, !isEmpty else {
            self.endTyping()
            return
        }
        self.postTyping(true)
        let sleep = self.sleep
        let idle = self.typingIdle
        self.typingIdleTask = Task { [weak self] in
            do {
                try await sleep(idle)
            } catch {
                return
            }
            await self?.endTyping()
        }
    }

    /// Tells the agent the visitor stopped typing, if they were last told otherwise.
    package func endTyping() {
        self.typingIdleTask?.cancel()
        self.typingIdleTask = nil
        self.postTyping(false)
    }

    /// Reads the message log again for a freshly signed link to attachment `attachmentId` — a
    /// file or an image — whose stored link may have expired. Nil when the log can't be read or
    /// no longer holds it. The read publishes nothing and leaves the message cursor where it is.
    package func freshURL(attachmentId: String) async -> URL? {
        let gen = self.generation
        let sync: LivechatSync
        do {
            sync = try await self.sync(after: 0, waiting: false)
        } catch .sessionExpired {
            // A 401 for a read started before a reset or delete belongs to the replaced visitor.
            self.expire(generation: gen)
            return nil
        } catch {
            // The caller falls back to the stored link while it is valid; a later tap reads again.
            return nil
        }
        for message in sync.messages.reversed() {
            for part in message.parts {
                switch part {
                case .file(let file) where file.attachmentId == attachmentId: return file.url
                case .image(let image) where image.attachmentId == attachmentId: return image.url
                default: continue
                }
            }
        }
        return nil
    }

    /// Stops polling, rewinds the cursor and publishes `inactive`. Called on reset and delete.
    /// Returns the generation that starts here: snapshots of an older one still in ``stream``
    /// belong to the session being replaced.
    @discardableResult
    package func teardown() -> UInt64 {
        self.bumpGeneration()
        self.sessionExpired = false
        self.afterSequence = 0
        self.consecutiveFailures = 0
        self.stopPolling()
        self.publishTransition(to: LivechatState(status: .inactive), messages: [])
        return self.generation
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

    /// Pauses polling while the app is in the background, and tells the agent typing stopped.
    package func setSceneActive(_ active: Bool) {
        self.isSceneActive = active
        if !active {
            self.endTyping()
        }
        self.resumeIfNeeded()
    }

    /// Pauses polling while the chat view is off screen but the chat is still alive, and tells the
    /// agent typing stopped.
    package func setVisible(_ visible: Bool) {
        self.isVisible = visible
        if !visible {
            self.endTyping()
        }
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
    /// The session's generation when this was published; see ``LivechatSession/teardown()``.
    package let generation: UInt64
    /// The first state the session published, found already in place rather than seen changing:
    /// its transition from `previousStatus` happened before this device was watching.
    package let isRestored: Bool
}
