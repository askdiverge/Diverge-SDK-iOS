//
//  LivechatSessionTests.swift
//  AIConversationTests
//

import Foundation
import Synchronization
import Testing
@testable import AIConversationEngine

@Suite("LivechatSession")
struct LivechatSessionTests {

    private static let serverError = ChatServiceError.transport(.http(.unhandled(status: 500, body: Data())))

    @Test("polls every 2 s while waiting")
    func waitingCadence() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            if log.count >= 2 { throw CancellationError() }
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(80))
        await session.stopPolling()
        #expect(log.values.contains(.seconds(2)))
    }

    @Test("polls every 3 s once active")
    func activeCadence() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            throw CancellationError()
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(80))
        await session.stopPolling()
        #expect(log.values.contains(.seconds(3)))
    }

    @Test("consecutive failures back off 2 s, 4 s, then reset on success")
    func backoffThenReset() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        service.livechatStateError = Self.serverError
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            if log.count == 2 { service.livechatStateError = nil }
            if log.count >= 3 { throw CancellationError() }
        }
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(120))
        await session.stopPolling()
        #expect(Array(log.values.prefix(3)) == [.seconds(2), .seconds(4), .seconds(2)])
    }

    @Test("bootstrap of an open session replays the log from the start and polls")
    func bootstrapInSession() async {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting),
            livechatMessagePages: [LivechatFixtures.page(LivechatFixtures.message("m1", role: .agent, sequence: 3))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        let outcome = await session.bootstrap()

        let snapshot = await snapshots.next()
        #expect(outcome == .inSession)
        #expect(snapshot?.state.status == .waiting)
        #expect(snapshot?.messages.map(\.messageId) == ["m1"])
        #expect(service.lastLivechatAfterSequence == nil)
        await session.stopPolling()
    }

    @Test("bootstrap without a session reads the state once and doesn't poll")
    func bootstrapIdle() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .inactive)))
        let session = LivechatSession(service: service) { _ in
            Issue.record("an idle bootstrap should not poll")
            throw CancellationError()
        }
        #expect(await session.bootstrap() == .notInSession)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 1)
    }

    @Test("bootstrap that can't read the state reports no session yet and retries with the poller")
    func bootstrapTransportFailure() async throws {
        let service = MockChatService(.init(livechatStateError: Self.serverError))
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            throw CancellationError()
        }

        #expect(await session.bootstrap() == .notInSession)
        try await Task.sleep(for: .milliseconds(40))
        #expect(log.values == [.seconds(2)])
    }

    @Test("bootstrap on a 401 reports the session expired")
    func bootstrapExpired() async {
        let service = MockChatService(.init(livechatStateError: .sessionExpired))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        #expect(await session.bootstrap() == .sessionExpired)
    }

    @Test("bootstrap after a 401 polls again once the state reads")
    func bootstrapAfterExpiryPolls() async throws {
        let service = MockChatService(.init(livechatStateError: .sessionExpired))
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            throw CancellationError()
        }
        #expect(await session.bootstrap() == .sessionExpired)

        service.livechatStateError = nil
        service.livechatState = LivechatState(status: .waiting)

        #expect(await session.bootstrap() == .inSession)
        try await Task.sleep(for: .milliseconds(40))
        #expect(log.values == [.seconds(2)])
    }

    @Test("a 401 while polling publishes sessionExpired and stops")
    func expiryStops() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        service.livechatStateError = .sessionExpired
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let stream = session.stream
        let expired = Task<LivechatSnapshot?, Never> {
            for await snapshot in stream where snapshot.sessionExpired { return snapshot }
            return nil
        }

        await session.startPolling(immediate: true)

        let snapshot = await expired.value
        #expect(snapshot?.state.status == .inactive)
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
    }

    @Test("when the session closes, the last messages are fetched and polling stops")
    func closedEdgeFetchesThenStops() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatMessagePages: [
                LivechatFixtures.page(),
                LivechatFixtures.page(LivechatFixtures.message("thanks", role: .agent))
            ]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Log<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.append(snapshot) }
        }

        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        try await Task.sleep(for: .milliseconds(40))
        collector.cancel()

        let closed = log.values.last
        #expect(closed?.state.status == .closed)
        #expect(closed?.previousStatus == .active)
        #expect(closed?.messages.map(\.messageId) == ["thanks"])
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
    }

    @Test("teardown publishes inactive and stops polling")
    func teardownStops() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in try await Task.sleep(for: .seconds(30)) }
        var snapshots = session.stream.makeAsyncIterator()
        await session.startPolling(immediate: true)
        _ = await snapshots.next()

        await session.teardown()

        #expect(await snapshots.next()?.state.status == .inactive)
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == calls)
    }

    @Test("handover publishes the status the server returns, then polls for the agent")
    func handoverUsesServerStatus() async throws {
        let service = MockChatService(.init(
            livechatState: try LivechatFixtures.activeState(agentName: "Alice"),
            livechatHandoverStatus: .active
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()
        let context = LivechatClientContext(currentPageUrl: "/products/sku", os: "iOS")

        try await session.handover(source: .manualButton, partId: nil, clientContext: context)

        #expect(await snapshots.next()?.state.status == .active)
        #expect(await snapshots.next()?.state.activeAgent?.displayName == "Alice")
        #expect(service.livechatHandoverCallCount == 1)
        #expect(service.lastLivechatHandoverClientContext == context)
        await session.stopPolling()
    }

    @Test("a handover whose follow-up state read fails still succeeds and keeps polling")
    func handoverSurvivesFailedRead() async throws {
        let service = MockChatService(.init(livechatStateError: Self.serverError))
        let log = Log<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.append(duration)
            throw CancellationError()
        }
        var snapshots = session.stream.makeAsyncIterator()

        try await session.handover(source: .manualButton, partId: nil)

        #expect(await snapshots.next()?.state.status == .waiting)
        try await Task.sleep(for: .milliseconds(40))
        #expect(log.values == [.seconds(2)])
    }

    @Test("a session adopted after an earlier one closed is read from its start")
    func adoptedSessionResetsCursor() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatMessagePages: [LivechatFixtures.page(LivechatFixtures.message("m40", role: .agent, sequence: 40))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        service.livechatState = LivechatState(status: .closed)
        await session.refresh()

        service.livechatState = LivechatState(status: .waiting)
        await session.refresh()
        #expect(service.lastLivechatAfterSequence == nil)

        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        await session.resumeActive()
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.lastLivechatAfterSequence == nil)
        await session.stopPolling()
    }

    @Test("messages are fetched page by page while has_more holds")
    func pagesUntilDone() async {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatMessagePages: [
                LivechatMessagePage(messages: [LivechatFixtures.message("m1", role: .agent, sequence: 1)], hasMore: true),
                LivechatFixtures.page(LivechatFixtures.message("m2", role: .agent, sequence: 2))
            ]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await session.bootstrap()

        #expect(await snapshots.next()?.messages.map(\.messageId) == ["m1", "m2"])
        #expect(service.lastLivechatAfterSequence == 1)
        await session.stopPolling()
    }

    @Test("a tick that changes nothing publishes nothing")
    func unchangedTickIsQuiet() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Log<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.append(snapshot) }
        }

        await session.bootstrap()
        await session.refresh()
        await session.refresh()
        try await Task.sleep(for: .milliseconds(20))
        await session.stopPolling()
        collector.cancel()

        #expect(log.count == 1)
    }

    @Test("polling ends once the last reference to the session is gone")
    func droppedSessionStopsPolling() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        var session: LivechatSession? = LivechatSession(service: service) { _ in
            try await Task.sleep(for: .milliseconds(5))
        }
        await session?.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(30))

        session = nil
        try await Task.sleep(for: .milliseconds(30))
        let calls = service.livechatStateCallCount
        try await Task.sleep(for: .milliseconds(40))

        #expect(service.livechatStateCallCount == calls)
    }

    @Test("a 409 on handover surfaces as conflict and publishes nothing")
    func handoverConflict() async throws {
        let service = MockChatService(.init(livechatHandoverError: .conflict))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Log<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.append(snapshot) }
        }

        await #expect(throws: ChatServiceError.self) {
            try await session.handover(source: .manualButton, partId: nil)
        }

        try await Task.sleep(for: .milliseconds(20))
        collector.cancel()
        #expect(log.values.isEmpty)
        #expect(service.livechatStateCallCount == 0)
    }

    @Test("an older state_version is dropped; a state without a version applies")
    func dropsStaleStateVersion() async throws {
        let service = MockChatService(.init(livechatState: LivechatFixtures.state(.active, version: 5)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Log<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.append(snapshot) }
        }

        await session.bootstrap()
        service.livechatState = LivechatFixtures.state(.waiting, version: 4)
        await session.refresh()
        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        try await Task.sleep(for: .milliseconds(20))
        await session.stopPolling()
        collector.cancel()

        #expect(log.values.map(\.state.status) == [.active, .closed])
    }

    @Test("a stale state doesn't fetch messages or move the cursor")
    func staleTickKeepsCursor() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatFixtures.state(.active, version: 5),
            livechatMessagePages: [LivechatFixtures.page(LivechatFixtures.message("m10", role: .agent, sequence: 10))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }

        await session.bootstrap()
        let messageCalls = service.livechatMessagesCallCount
        service.livechatState = LivechatFixtures.state(.active, version: 4)
        await session.refresh()

        #expect(service.livechatMessagesCallCount == messageCalls)
        service.livechatState = LivechatFixtures.state(.active, version: 6)
        await session.refresh()
        #expect(service.lastLivechatAfterSequence == 10)
        await session.stopPolling()
    }

    @Test("a new generation accepts a lower state_version")
    func generationResetsVersionWatermark() async {
        let service = MockChatService(.init(livechatState: LivechatFixtures.state(.waiting, version: 50)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await session.bootstrap()
        await session.teardown()
        service.livechatState = LivechatFixtures.state(.waiting, version: 1)
        await session.bootstrap()

        var versions: [Int?] = []
        for _ in 0..<3 { versions.append(await snapshots.next()?.state.stateVersion) }
        #expect(versions == [50, nil, 1])
        await session.stopPolling()
    }

    @Test("an inactive scene parks the loop; activating it ticks at once")
    func sceneGateCatchUp() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in try await Task.sleep(for: .seconds(30)) }

        await session.setSceneActive(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 0)

        await session.setSceneActive(true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 1)
        await session.stopPolling()
    }

    @Test("an off-screen chat parks the loop; showing it ticks at once")
    func visibilityGateCatchUp() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in try await Task.sleep(for: .seconds(30)) }

        await session.setVisible(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 0)

        await session.setVisible(true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatStateCallCount == 1)
        await session.stopPolling()
    }

    @Test("stop() releases a parked loop")
    func stopReleasesParkedLoop() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in try await Task.sleep(for: .seconds(30)) }
        await session.setVisible(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(20))

        session.stop()
        await session.setVisible(true)
        try await Task.sleep(for: .milliseconds(40))

        #expect(service.livechatStateCallCount == 0)
    }

    @Test("close retries the state read once when it fails")
    func closeRetriesStateFetch() async throws {
        let closed = try LivechatFixtures.decoder.decode(LivechatState.self, from: Data("""
        {
          "status": "closed", "active_agent": null, "is_agent_typing": false,
          "feedback": { "status": "pending", "submitted_at": null }
        }
        """.utf8))
        let service = MockChatService(.init(
            livechatState: closed,
            livechatStateFailingCalls: [0: Self.serverError]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        try await session.close(reason: "visitor_left")

        let snapshot = await snapshots.next()
        #expect(snapshot?.state.status == .closed)
        #expect(snapshot?.state.feedback.status == .pending)
        #expect(service.livechatStateCallCount == 2)
        #expect(service.livechatCloseCallCount == 1)
    }

    @Test("close reports feedback pending when both state reads fail")
    func closeFallsBackToPending() async throws {
        let service = MockChatService(.init(livechatStateError: Self.serverError))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        try await session.close(reason: "visitor_left")

        let snapshot = await snapshots.next()
        #expect(snapshot?.state.status == .closed)
        #expect(snapshot?.state.feedback.status == .pending)
        #expect(service.livechatStateCallCount == 2)
    }
}

/// Values appended from the poller's tasks and read by the test.
private final class Log<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    var values: [Value] { self.storage.withLock { $0 } }
    var count: Int { self.storage.withLock { $0.count } }

    func append(_ value: Value) {
        self.storage.withLock { $0.append(value) }
    }
}
