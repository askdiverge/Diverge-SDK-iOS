//
//  LivechatSessionTypingTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversationEngine

extension LivechatSessionTests {

    // MARK: Visitor typing

    @Test("typing posts true once per burst, and false after the idle pause")
    func typingBurst() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service, typingIdle: Self.testIdle, sleep: Self.idleOnly)
        await session.bootstrap()

        await session.visitorTyping(isEmpty: false)
        await session.visitorTyping(isEmpty: false)

        try await eventually { service.livechatTypingEvents == [true, false] }
    }

    @Test("clearing the draft tells the agent typing stopped")
    func clearedDraftEndsTyping() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        await session.visitorTyping(isEmpty: false)
        try await eventually { service.livechatTypingEvents == [true] }

        await session.visitorTyping(isEmpty: true)

        try await eventually { service.livechatTypingEvents == [true, false] }
    }

    @Test("a false post waits for the true post before it, so they arrive in order")
    func typingPostsInOrder() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        let entered = AsyncGate()
        let release = AsyncGate()
        service.livechatTypingHold = { isTyping in
            guard isTyping else { return }
            await entered.open()
            await release.wait()
        }
        await session.bootstrap()

        await session.visitorTyping(isEmpty: false)
        await entered.wait()
        await session.endTyping()
        await release.open()

        try await eventually { service.livechatTypingEvents == [true, false] }
    }

    @Test("a failed typing post is retried, so the agent still sees the visitor typing")
    func failedTypingPostRetries() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatTypingFailures: 1
        ))
        let session = LivechatSession(service: service, typingIdle: Self.testIdle, sleep: Self.idleWaits)
        await session.bootstrap()
        await session.stopPolling()

        await session.visitorTyping(isEmpty: false)

        try await eventually { service.livechatTypingEvents == [true] }
    }

    @Test("leaving the active state drops typing without a post, and typing outside a session posts nothing")
    func typingEndsWithSession() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        await session.visitorTyping(isEmpty: false)
        try await eventually { service.livechatTypingEvents == [true] }

        service.livechatState = LivechatState(status: .closed)
        await session.refresh()
        await session.visitorTyping(isEmpty: false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.livechatTypingEvents == [true])
    }

    @Test("a typing post that finds the visitor session ended (401) ends it, without a retry")
    func typingExpiryEndsSession() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatTypingError: .sessionExpired
        ))
        let session = LivechatSession(service: service, typingIdle: Self.testIdle, sleep: Self.idleWaits)
        var snapshots = session.stream.makeAsyncIterator()
        await session.bootstrap()
        _ = await snapshots.next()
        await session.stopPolling()

        await session.visitorTyping(isEmpty: false)

        #expect(await snapshots.next()?.sessionExpired == true)
        #expect(service.livechatTypingAttempts == 1)
    }

    @Test("a refused typing post isn't retried")
    func refusedTypingPostIsNotRetried() async throws {
        let service = MockChatService(.init(
            livechatState: LivechatState(status: .active),
            livechatTypingError: .transport(.http(.unhandled(status: 409, body: Data())))
        ))
        let session = LivechatSession(service: service, typingIdle: Self.testIdle, sleep: Self.idleWaits)
        await session.bootstrap()
        await session.stopPolling()

        await session.visitorTyping(isEmpty: false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.livechatTypingAttempts == 1)
    }

    @Test("teardown drops typing without telling the agent, as delete and reset do")
    func teardownPostsNoTyping() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        await session.visitorTyping(isEmpty: false)
        try await eventually { service.livechatTypingEvents == [true] }

        await session.teardown()
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.livechatTypingEvents == [true])
    }

    @Test("a chat that goes off screen tells the agent typing stopped")
    func offScreenEndsTyping() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        await session.visitorTyping(isEmpty: false)
        try await eventually { service.livechatTypingEvents == [true] }

        await session.setVisible(false)

        try await eventually { service.livechatTypingEvents == [true, false] }
    }

    @Test("a session that expires mid-burst clears typing without posting with a stale token")
    func expiryEndsTypingSilently() async throws {
        let service = MockChatService(.init(livechatState: LivechatState(status: .active)))
        let session = LivechatSession(service: service) { _ in throw CancellationError() }
        await session.bootstrap()
        await session.visitorTyping(isEmpty: false)
        try await eventually { service.livechatTypingEvents == [true] }

        service.livechatStateError = .sessionExpired
        await session.refresh()
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.livechatTypingEvents == [true])
    }
}
