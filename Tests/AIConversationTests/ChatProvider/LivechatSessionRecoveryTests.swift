//
//  LivechatSessionRecoveryTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

extension LivechatSessionTests {

    @Test("a 409 on handover surfaces as conflict and publishes nothing")
    func handoverConflict() async throws {
        let service = MockChatService(.init(livechatHandoverError: .conflict))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Recorder<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.record(snapshot) }
        }

        await #expect(throws: ChatServiceError.self) {
            try await session.handover(source: .manualButton, partId: nil)
        }

        try await Task.sleep(for: .milliseconds(20))
        collector.cancel()
        #expect(log.values.isEmpty)
        #expect(service.livechatSyncCallCount == 0)
    }

    @Test("an older state_version that a fresh read doesn't repeat is dropped; a state without a version applies")
    func dropsStaleStateVersion() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatFixtures.state(.active, version: 5),
            livechatStateByCall: [1: LivechatFixtures.state(.waiting, version: 4)]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Recorder<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.record(snapshot) }
        }

        await session.bootstrap()
        await session.refresh()
        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        try await Task.sleep(for: .milliseconds(20))
        await session.stopPolling()
        collector.cancel()

        #expect(log.values.map(\.state.status) == [.active, .closed])
    }

    @Test("a stale snapshot is dropped without moving the cursor")
    func staleTickKeepsCursor() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatFixtures.state(.active, version: 5),
            livechatStateByCall: [1: LivechatFixtures.state(.active, version: 4)],
            livechatMessagePages: [
                LivechatFixtures.page(LivechatFixtures.message("m10", role: .agent, sequence: 10)),
                LivechatFixtures.page(LivechatFixtures.message("m11", role: .agent, sequence: 11))
            ]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }

        await session.bootstrap()
        await session.refresh()
        service.livechatState = LivechatFixtures.state(.active, version: 6)
        await session.refresh()

        #expect(service.lastLivechatAfterSequence == 10)
        await session.stopPolling()
    }

    @Test("a lower state_version that a fresh read repeats is a replacement session, read from its start")
    func replacementSessionReadsFromStart() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatFixtures.state(.active, version: 5),
            livechatMessagePages: [
                LivechatFixtures.page(LivechatFixtures.message("old", role: .agent, sequence: 10)),
                LivechatFixtures.page(),
                LivechatFixtures.page(),
                LivechatFixtures.page(LivechatFixtures.message("new", role: .agent, sequence: 1))
            ]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let log = Recorder<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.record(snapshot) }
        }

        await session.bootstrap()
        service.livechatState = LivechatFixtures.state(.active, version: 1)
        await session.refresh()
        try await Task.sleep(for: .milliseconds(20))
        await session.stopPolling()
        collector.cancel()

        #expect(service.livechatSyncCallCount == 4)
        #expect(service.lastLivechatAfterSequence == nil)
        #expect(log.values.flatMap(\.messages).map(\.messageId) == ["old", "new"])
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
        #expect(service.livechatSyncCallCount == 0)

        await session.setSceneActive(true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatSyncCallCount == 1)
        await session.stopPolling()
    }

    @Test("an off-screen chat parks the loop; showing it ticks at once")
    func visibilityGateCatchUp() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in try await Task.sleep(for: .seconds(30)) }

        await session.setVisible(false)
        await session.startPolling(immediate: true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatSyncCallCount == 0)

        await session.setVisible(true)
        try await Task.sleep(for: .milliseconds(40))
        #expect(service.livechatSyncCallCount == 1)
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

        #expect(service.livechatSyncCallCount == 0)
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
        #expect(service.livechatSyncCallCount == 2)
        #expect(service.livechatCloseCallCount == 1)
    }

    @Test("a 401 on the read after a close ends the visitor session")
    func closeThenExpiry() async {
        let service = MockChatService(.init(livechatStateError: .sessionExpired))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await #expect(throws: ChatServiceError.self) {
            try await session.close(reason: "visitor_left")
        }

        #expect(await snapshots.next()?.sessionExpired == true)
        #expect(service.livechatSyncCallCount == 1)
    }

    @Test("bootstrap publishes the log of a session that closed before it ran")
    func bootstrapClosedSession() async {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .closed),
            livechatMessagePages: [LivechatFixtures.page(LivechatFixtures.message("bye", role: .agent, sequence: 4))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        #expect(await session.bootstrap() == .notInSession)

        let snapshot = await snapshots.next()
        #expect(snapshot?.state.status == .closed)
        #expect(snapshot?.messages.map(\.messageId) == ["bye"])
    }

    @Test("teardown returns the generation its own and later snapshots carry")
    func teardownGeneration() async {
        let service = MockChatService(.init(livechatState: LivechatState(status: .waiting)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await session.bootstrap()
        let generation = await session.teardown()

        let before = await snapshots.next()
        let after = await snapshots.next()
        #expect(before.map { $0.generation < generation } == true)
        #expect(after?.generation == generation)
        #expect(after?.state.status == .inactive)
    }

    @Test("a recovery read that fails after a 409 leaves the poller retrying it")
    func failedRecoveryReadKeepsPolling() async throws {
        let service = MockChatService(.init(livechatStateError: Self.serverError))
        let log = Recorder<Duration>()
        let session = LivechatSession(service: service) { duration in
            log.record(duration)
            throw CancellationError()
        }

        #expect(await session.resumeActive() == false)
        try await Task.sleep(for: .milliseconds(40))

        #expect(log.count == 1)
    }

    @Test("a recovery read that finds the session closed publishes its last messages")
    func recoveryReadOfClosedSession() async {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .closed),
            livechatMessagePages: [LivechatFixtures.page(LivechatFixtures.message("bye", role: .agent, sequence: 3))]
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        #expect(await session.resumeActive() == false)

        let snapshot = await snapshots.next()
        #expect(snapshot?.state.status == .closed)
        #expect(snapshot?.messages.map(\.messageId) == ["bye"])
    }

    @Test("a handover whose response was lost polls for the session it may have opened")
    func lostHandoverResponsePolls() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .waiting),
            livechatHandoverError: .transport(.connection(URLError(.timedOut)))
        ))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await #expect(throws: ChatServiceError.self) {
            try await session.handover(source: .manualButton, partId: nil)
        }

        #expect(await snapshots.next()?.state.status == .waiting)
        #expect(service.livechatSyncCallCount == 1)
    }

    @Test("a 401 for a link refresh started before a teardown doesn't end the new session")
    func staleRefreshExpiryIsIgnored() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let entered = AsyncGate()
        let release = AsyncGate()
        service.livechatSyncHold = {
            await entered.open()
            await release.wait()
        }
        let log = Recorder<LivechatSnapshot>()
        let collector = Task {
            for await snapshot in session.stream { log.record(snapshot) }
        }

        let refresh = Task { await session.freshURL(attachmentId: "att_1") }
        await entered.wait()
        await session.teardown()
        service.livechatStateError = .sessionExpired
        await release.open()
        _ = await refresh.value
        try await Task.sleep(for: .milliseconds(20))
        collector.cancel()

        #expect(!log.values.contains { $0.sessionExpired })
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
        #expect(service.livechatSyncCallCount == 2)
    }

    // MARK: Restored state

    @Test("the first state read is marked restored, and later changes are live")
    func firstReadIsRestored() async {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        await session.bootstrap()
        #expect(await snapshots.next()?.isRestored == true)

        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        #expect(await snapshots.next()?.isRestored == false)
    }

    @Test("a handover is live even as the first state published")
    func handoverIsLive() async throws {
        let service = MockChatService()
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        var snapshots = session.stream.makeAsyncIterator()

        try await session.handover(source: .manualButton, partId: nil)

        let snapshot = await snapshots.next()
        #expect(snapshot?.state.status == .waiting)
        #expect(snapshot?.isRestored == false)
        await session.stopPolling()
    }
}
