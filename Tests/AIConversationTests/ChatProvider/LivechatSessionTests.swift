//
//  LivechatSessionTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("LivechatSession")
struct LivechatSessionTests {

    final class SleepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _sleeps: [Duration] = []
        var sleeps: [Duration] {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self._sleeps
        }
        func record(_ duration: Duration) {
            self.lock.lock()
            self._sleeps.append(duration)
            self.lock.unlock()
        }
    }

    final class SnapshotLog: @unchecked Sendable {
        private let lock = NSLock()
        private var snaps: [LivechatSnapshot] = []
        func append(_ snap: LivechatSnapshot) {
            self.lock.lock()
            self.snaps.append(snap)
            self.lock.unlock()
        }
        var statuses: [LivechatState.Status] {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.snaps.map(\.state.status)
        }
    }

    @Test("poll cadence is 2s waiting")
    func waitingCadence() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting)
        ))
        let log = SleepLog()
        let session = LivechatSession(service: service) { duration in
            log.record(duration)
            if log.sleeps.count >= 2 { throw CancellationError() }
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(80))
        await session.stopPolling()
        #expect(log.sleeps.contains(where: { $0 == .seconds(2) }))
    }

    @Test("poll cadence is 3s when last status is active")
    func activeCadence() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active)
        ))
        let log = SleepLog()
        let session = LivechatSession(service: service) { duration in
            log.record(duration)
            if log.sleeps.count >= 1 { throw CancellationError() }
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(80))
        await session.stopPolling()
        #expect(log.sleeps.contains(where: { $0 == .seconds(3) }))
    }

    @Test("consecutive failures back off 2, 4 then reset on success")
    func backoffThenReset() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting)
        ))
        service.livechatStateError = .transport(.http(.unhandled(status: 500)))
        let log = SleepLog()
        let session = LivechatSession(service: service) { duration in
            log.record(duration)
            if log.sleeps.count == 2 {
                service.livechatStateError = nil
            }
            if log.sleeps.count >= 3 { throw CancellationError() }
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(120))
        await session.stopPolling()
        let sleeps = log.sleeps
        #expect(sleeps.count >= 2)
        #expect(sleeps[0] == .seconds(2))
        #expect(sleeps[1] == .seconds(4))
        if sleeps.count >= 3 {
            #expect(sleeps[2] == .seconds(2))
        }
    }

    @Test("bootstrap of a waiting session replays from 0 and starts polling")
    func bootstrapInSession() async throws {
        let page = LivechatMessagePage(
            messages: [
                LivechatMessage(
                    messageId: "m1",
                    role: .agent,
                    agent: LivechatAgent(agentId: "a", displayName: "Alice"),
                    parts: [],
                    createdAt: "2025-01-01T00:00:00Z",
                    sequenceNumber: 3
                )
            ],
            hasMore: false
        )
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting),
            livechatMessagePages: [page]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let collector = Task {
            var snaps: [LivechatSnapshot] = []
            for await snap in stream {
                snaps.append(snap)
                if snaps.count >= 1 { return snaps }
            }
            return snaps
        }
        await session.bootstrap()
        let snaps = await collector.value
        #expect(snaps.first?.state.status == .waiting)
        #expect(snaps.first?.messages.first?.messageId == "m1")
        #expect(service.lastLivechatAfterSequence == nil)
        await session.stopPolling()
    }

    @Test("bootstrap of inactive does not start polling")
    func bootstrapIdle() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .inactive)))
        let session = LivechatSession(service: service) { _ in
            Issue.record("idle bootstrap should not poll")
            throw CancellationError()
        }
        await session.bootstrap()
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 1)
        await session.stopPolling()
    }

    @Test("bootstrap transport failure publishes inactive and returns notInSession")
    func bootstrapTransportOutcome() async {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting),
            livechatStateError: .transport(.http(.unhandled(status: 500)))
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let outcome = await session.bootstrap()
        #expect(outcome == .notInSession)
        await session.stopPolling()
    }

    @Test("401 stops the loop and publishes sessionExpired")
    func expiryStops() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        service.livechatStateError = .sessionExpired
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let collector = Task<LivechatSnapshot?, Never> {
            for await snap in stream {
                if snap.sessionExpired { return snap }
            }
            return nil
        }
        await session.startPolling(immediate: true)
        let snap = await collector.value
        #expect(snap?.sessionExpired == true)
        #expect(snap?.state.status == .inactive)
        try await Task.sleep(for: .milliseconds(40))
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
        await session.stopPolling()
    }

    @Test("leaving a session fetches remaining messages on the closed edge then stops")
    func closedEdgeFetchesThenStops() async throws {
        let greeting = LivechatMessage(
            messageId: "thanks",
            role: .agent,
            agent: LivechatAgent(agentId: "a", displayName: "Alice"),
            parts: [],
            createdAt: "2025-01-01T00:00:00Z",
            sequenceNumber: 1
        )
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatMessagePages: [
                LivechatMessagePage(messages: [], hasMore: false),
                LivechatMessagePage(messages: [greeting], hasMore: false),
            ]
        ))
        let session = LivechatSession(service: service) { duration in
            service.livechatState = LivechatState(status: .closed)
            throw CancellationError()
        }
        let stream = session.stream
        let collector = Task {
            var snaps: [LivechatSnapshot] = []
            for await snap in stream {
                snaps.append(snap)
                if snaps.contains(where: { $0.state.status == .closed }) { return snaps }
            }
            return snaps
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(80))
        // The sleep callback flipped state to closed but cancelled before the next tick.
        // Drive a refresh as close() would after the visitor/agent close.
        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        let snaps = await collector.value
        #expect(snaps.contains(where: { $0.state.status == .closed }))
        #expect(snaps.contains(where: { $0.messages.contains(where: { $0.messageId == "thanks" }) }))
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
        await session.stopPolling()
    }

    @Test("teardown publishes inactive and stops polling")
    func teardownStops() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in
            try await Task.sleep(for: .seconds(30))
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        await session.teardown()
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
    }

    @Test("handover fetches state (reused active is not forced to waiting)")
    func handoverUsesServerStatus() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(
                status: .active,
                activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
            )
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let collector = Task<LivechatSnapshot?, Never> {
            for await snap in stream { return snap }
            return nil
        }
        let context = LivechatClientContext(currentPageUrl: "/products/sku", os: "iOS")
        try await session.handover(source: "manual_button", partId: nil, clientContext: context)
        let snap = await collector.value
        #expect(snap?.state.status == .active)
        #expect(snap?.state.activeAgent?.displayName == "Alice")
        #expect(service.livechatHandoverCallCount == 1)
        #expect(service.lastLivechatHandoverClientContext == context)
        await session.stopPolling()
    }

    @Test("stale state_version ticks are dropped; missing version still applies")
    func dropsStaleStateVersion() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active, stateVersion: 5)
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let collector = Task {
            var snaps: [LivechatSnapshot] = []
            for await snap in stream {
                snaps.append(snap)
                if snaps.count >= 2 { break }
            }
            return snaps
        }
        _ = await session.bootstrap()
        service.livechatState = LivechatState(status: .waiting, stateVersion: 4)
        await session.refresh()
        service.livechatState = LivechatState(status: .closed) // nil version
        await session.refresh()
        try await Task.sleep(for: .milliseconds(40))
        await session.stopPolling()
        let snaps = await collector.value
        #expect(snaps.map(\.state.status) == [.active, .closed])
        #expect(!snaps.contains(where: { $0.state.status == .waiting }))
    }

    @Test("stale /state does not fetch messages or advance the cursor")
    func staleTickDoesNotAdvanceMessageCursor() async throws {
        let throughTen = LivechatMessagePage(
            messages: [
                LivechatMessage(
                    messageId: "m10",
                    role: .agent,
                    agent: LivechatAgent(agentId: "a", displayName: "Alice"),
                    parts: [],
                    createdAt: "2025-01-01T00:00:00Z",
                    sequenceNumber: 10
                )
            ],
            hasMore: false
        )
        let laterPage = LivechatMessagePage(
            messages: [
                LivechatMessage(
                    messageId: "m11",
                    role: .agent,
                    agent: LivechatAgent(agentId: "a", displayName: "Alice"),
                    parts: [],
                    createdAt: "2025-01-01T00:00:01Z",
                    sequenceNumber: 11
                )
            ],
            hasMore: false
        )
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active, stateVersion: 5),
            livechatMessagePages: [throughTen]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = SnapshotLog()
        let collector = Task {
            for await snap in session.stream {
                log.append(snap)
            }
        }
        _ = await session.bootstrap()
        let messagesAfterBootstrap = service.livechatMessagesCallCount
        let afterAfterBootstrap = service.lastLivechatAfterSequence
        service.livechatMessagePages = [throughTen, laterPage]
        service.livechatState = LivechatState(status: .waiting, stateVersion: 4)
        await session.refresh()
        try await Task.sleep(for: .milliseconds(40))
        await session.stopPolling()
        collector.cancel()
        #expect(service.livechatMessagesCallCount == messagesAfterBootstrap)
        #expect(service.lastLivechatAfterSequence == afterAfterBootstrap)
        #expect(log.statuses == [.active])
    }

    @Test("generation bump resets the version watermark so a new session at v1 applies")
    func generationResetsVersionWatermark() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting, stateVersion: 50)
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let collector = Task {
            var snaps: [LivechatSnapshot] = []
            for await snap in stream {
                snaps.append(snap)
                if snaps.count >= 3 { break }
            }
            return snaps
        }
        _ = await session.bootstrap()
        await session.teardown()
        service.livechatState = LivechatState(status: .waiting, stateVersion: 1)
        _ = await session.bootstrap()
        try await Task.sleep(for: .milliseconds(40))
        await session.stopPolling()
        let snaps = await collector.value
        let statuses = snaps.map(\.state.status)
        let versions = snaps.compactMap(\.state.stateVersion)
        #expect(statuses.contains(.waiting))
        #expect(statuses.contains(.inactive))
        #expect(versions.contains(50))
        #expect(versions.contains(1))
    }

    @Test("setActive(false) parks; setActive(true) ticks immediately")
    func sceneGateCatchUp() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let parked = SleepLog()
        let session = LivechatSession(service: service) { duration in
            parked.record(duration)
            try await Task.sleep(for: .seconds(30))
        }
        await session.setActive(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        let callsWhileParked = service.livechatStateCallCount
        #expect(callsWhileParked == 0)
        await session.setActive(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(service.livechatStateCallCount > callsWhileParked)
        await session.stopPolling()
    }

    @Test("setVisible(false) parks; setVisible(true) ticks immediately")
    func visibilityGateCatchUp() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let parked = SleepLog()
        let session = LivechatSession(service: service) { duration in
            parked.record(duration)
            try await Task.sleep(for: .seconds(30))
        }
        await session.setVisible(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        let callsWhileParked = service.livechatStateCallCount
        #expect(callsWhileParked == 0)
        await session.setVisible(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(service.livechatStateCallCount > callsWhileParked)
        await session.stopPolling()
    }

    @Test("note minting appends a note turn")
    func noteMinting() async throws {
        let service = MockChatService()
        let provider = ChatProvider(service: service, pageContext: { nil })
        let stream = provider.stream
        let collector = Task {
            var snapshots: [ConversationSnapshot] = []
            for await snap in stream {
                snapshots.append(snap)
                if snapshots.count >= 1 { return snapshots }
            }
            return snapshots
        }
        await provider.note(LivechatNote(kind: .queued))
        let snapshots = await collector.value
        #expect(snapshots.last?.turns.contains { if case .note = $0.model { return true }; return false } == true)
    }

    @Test("human agent marker gated when acceptsHumanAgentPrompts is false")
    func markerGate() async throws {
        let service = MockChatService(.init(historyPages: [
            MessagePage(messages: [
                Message(
                    messageId: "m1",
                    role: .assistant,
                    parts: [.requestHumanAgent(RequestHumanAgent(partId: "p1"))],
                    createdAt: "2025-01-01T00:00:00Z"
                )
            ], nextCursor: nil)
        ]))
        let provider = ChatProvider(
            service: service,
            pageContext: { nil },
            acceptsHumanAgentPrompts: false
        )
        _ = try await provider.loadOlder()
        let stream = provider.stream
        var last: ConversationSnapshot?
        for await snap in stream {
            last = snap
            break
        }
        let hasPrompt = last?.turns.contains { turn in
            if case .bot(let responses) = turn.model {
                return responses.contains { if case .requestHumanAgent = $0 { return true }; return false }
            }
            return false
        } ?? false
        #expect(!hasPrompt)
    }

    @Test("close retries GET state when the first fetch fails")
    func closeRetriesStateFetch() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(
                status: .closed,
                feedback: LivechatState.Feedback(status: .pending)
            ),
            livechatStateFailingCalls: [0: .transport(.http(.unhandled(status: 500)))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let collector = Task<LivechatSnapshot?, Never> {
            for await snap in session.stream { return snap }
            return nil
        }
        try await session.close(reason: "visitor_left")
        let snap = await collector.value
        #expect(snap?.state.status == .closed)
        #expect(snap?.state.feedback.status == .pending)
        #expect(service.livechatStateCallCount == 2)
        #expect(service.livechatCloseCallCount == 1)
        await session.stopPolling()
    }

    @Test("close synthesizes pending when both GETs fail after a successful close")
    func closeFallbackPendingWhenStateFetchFails() async throws {
        let service = MockChatService(.init(
            livechatStateError: .transport(.http(.unhandled(status: 500)))
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let collector = Task<LivechatSnapshot?, Never> {
            for await snap in session.stream { return snap }
            return nil
        }
        try await session.close(reason: "visitor_left")
        let snap = await collector.value
        #expect(snap?.state.status == .closed)
        #expect(snap?.state.feedback.status == .pending)
        #expect(service.livechatStateCallCount == 2)
        await session.stopPolling()
    }
}
