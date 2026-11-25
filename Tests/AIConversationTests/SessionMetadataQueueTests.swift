//
//  SessionMetadataQueueTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@MainActor
@Suite("SessionMetadataQueue — order, merging, retry and drop")
struct SessionMetadataQueueTests {

    @Test("nothing is sent before a chat is attached; then what waits goes in call order")
    func waitsForChat() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        sut.enqueue(Self.metadata("checkout"))
        sut.enqueue(Self.signed("token"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.sent.isEmpty)

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [Self.metadata("checkout"), Self.signed("token")])
    }

    @Test("the newest waiting token replaces the one before it, and unsigned calls merge around it")
    func keepsNewestWaitingToken() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        sut.enqueue(Self.signed("signed at login"))
        sut.enqueue(Self.metadata("home"))
        sut.enqueue(Self.signed("signed as the chat opens"))
        sut.enqueue(Self.metadata("checkout"))

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.attempts == 2 }
        #expect(patcher.sent == [Self.metadata("checkout"), Self.signed("signed as the chat opens")])
    }

    @Test("a token on its way is sent; the newest of those set meanwhile follows it")
    func tokenOnItsWayIsKept() async throws {
        let gate = AsyncGate()
        let (sut, patcher, chat) = Self.makeSUT(gate: gate)
        sut.enqueue(Self.signed("first"))
        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.attempts == 1 }

        sut.enqueue(Self.signed("second"))
        sut.enqueue(Self.signed("third"))
        await gate.open()

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [Self.signed("first"), Self.signed("third")])
    }

    @Test("unsigned calls waiting for a chat go as one patch, merged as the backend merges them")
    func mergesWaitingMetadata() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        sut.enqueue(.init(
            metadata: ["screen": .string("home"), "cart": .object(["items": .int(1)]), "tags": .array([.string("a")])],
            signedMetadata: nil
        ))
        sut.enqueue(.init(
            metadata: ["screen": .string("checkout"), "cart": .object(["total": .double(49.5)]), "tags": .array([])],
            signedMetadata: nil
        ))

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.attempts == 1 }
        #expect(patcher.sent == [.init(
            metadata: [
                "screen": .string("checkout"),
                "cart": .object(["items": .int(1), "total": .double(49.5)]),
                "tags": .array([])
            ],
            signedMetadata: nil
        )])
    }

    @Test("an object set over another kind of value goes as its own patch")
    func objectOverOtherValueGoesSeparately() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        let cleared = SessionMetadataPatchRequest(metadata: ["cart": .null], signedMetadata: nil)
        let refilled = SessionMetadataPatchRequest(metadata: ["cart": .object(["items": .int(2)])], signedMetadata: nil)
        sut.enqueue(cleared)
        sut.enqueue(refilled)

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [cleared, refilled])
    }

    @Test("a call made while a patch is on its way goes after it, and later calls merge into that one")
    func mergesBehindPatchOnItsWay() async throws {
        let gate = AsyncGate()
        let (sut, patcher, chat) = Self.makeSUT(gate: gate)
        sut.enqueue(Self.metadata("first"))
        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.attempts == 1 }

        sut.enqueue(Self.metadata("second"))
        sut.enqueue(Self.metadata("third"))
        await gate.open()

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [Self.metadata("first"), Self.metadata("third")])
    }

    @Test(
        "a patch answered 408, 429 or 5xx stays queued, with those after it, until the next attach",
        arguments: [408, 429, 500, 503]
    )
    func transientFailureKeepsQueue(status: Int) async throws {
        let (sut, patcher, chat) = Self.makeSUT(
            failures: [0: .transport(.http(.unhandled(status: status, body: Data())))]
        )
        sut.enqueue(Self.metadata("first"))
        sut.enqueue(Self.signed("token"))

        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.attempts == 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.attempts == 1)

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [Self.metadata("first"), Self.signed("token")])
    }

    @Test("a 401 drops the patch, as the web widget drops every 4xx")
    func unauthorizedDropsPatch() async throws {
        let (sut, patcher, chat) = Self.makeSUT(failures: [0: .sessionExpired])
        sut.enqueue(Self.signed("token"))
        sut.enqueue(Self.metadata("next"))

        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.sent == [Self.metadata("next")] }
        sut.attach(patcher.patch, for: chat)
        try await Task.sleep(for: .milliseconds(50))

        #expect(patcher.attempts == 2)
    }

    @Test("a 409 drops the patch: the backend has no session for it")
    func conflictDropsPatch() async throws {
        let (sut, patcher, chat) = Self.makeSUT(failures: [0: .conflict])
        sut.enqueue(Self.signed("token"))
        sut.enqueue(Self.metadata("next"))

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.sent == [Self.metadata("next")] }
        #expect(patcher.attempts == 2)
    }

    @Test("a patch the backend refuses is dropped and the next one goes")
    func refusedPatchIsDropped() async throws {
        let refused = ChatServiceError.validation(message: "signed_metadata token has expired", params: [])
        let (sut, patcher, chat) = Self.makeSUT(failures: [0: refused])
        sut.enqueue(Self.signed("expired"))
        sut.enqueue(Self.metadata("next"))

        sut.attach(patcher.patch, for: chat)

        try await eventually { patcher.sent == [Self.metadata("next")] }
        #expect(patcher.attempts == 2)
    }

    @Test("a detached chat sends nothing; what is queued goes through the next chat attached")
    func detachedChatSendsNothing() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        let (next, nextChat) = (ScriptedPatcher(failures: [:], gate: nil), NSObject())
        sut.attach(patcher.patch, for: chat)

        sut.detach(chat)
        sut.enqueue(Self.metadata("checkout"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.attempts == 0)

        sut.attach(next.patch, for: nextChat)

        try await eventually { next.sent == [Self.metadata("checkout")] }
        #expect(patcher.attempts == 0)
    }

    @Test("detaching stops the patch on its way, which goes again through the next chat")
    func detachStopsDelivery() async throws {
        let gate = AsyncGate()
        let (sut, patcher, chat) = Self.makeSUT(gate: gate)
        let (next, nextChat) = (ScriptedPatcher(failures: [:], gate: nil), NSObject())
        sut.enqueue(Self.metadata("checkout"))
        sut.enqueue(Self.signed("token"))
        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.attempts == 1 }

        sut.detach(chat)
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.attempts == 1)

        sut.attach(next.patch, for: nextChat)

        try await eventually { next.sent.count == 2 }
        #expect(next.sent == [Self.metadata("checkout"), Self.signed("token")])
    }

    @Test("a chat that leaves the screen after another was attached leaves that one sending")
    func staleDetachIsIgnored() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        let (next, nextChat) = (ScriptedPatcher(failures: [:], gate: nil), NSObject())
        sut.attach(patcher.patch, for: chat)
        sut.attach(next.patch, for: nextChat)

        sut.detach(chat)
        sut.enqueue(Self.metadata("checkout"))

        try await eventually { next.sent == [Self.metadata("checkout")] }
        #expect(patcher.attempts == 0)
    }

    @Test("a chat that went away without detaching sends nothing")
    func deallocatedChatSendsNothing() async throws {
        let (sut, patcher, _) = Self.makeSUT()
        do {
            let gone = NSObject()
            sut.attach(patcher.patch, for: gone)
        }

        sut.enqueue(Self.metadata("checkout"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(patcher.attempts == 0)
    }

    @Test("clear drops what is queued and detaches the chat")
    func clearDropsAndDetaches() async throws {
        let (sut, patcher, chat) = Self.makeSUT()
        sut.enqueue(Self.metadata("old visitor"))
        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.sent.count == 1 }

        sut.enqueue(Self.signed("old visitor's token"))
        sut.clear()
        sut.enqueue(Self.metadata("new visitor"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.sent == [Self.metadata("old visitor")])

        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent.last == Self.metadata("new visitor"))
    }

    @Test("clear while a patch is on its way leaves the next visitor's queue to itself")
    func clearDuringDelivery() async throws {
        let gate = AsyncGate()
        let (sut, patcher, chat) = Self.makeSUT(gate: gate)
        let next = ScriptedPatcher(failures: [:], gate: nil)
        sut.enqueue(Self.metadata("old visitor"))
        sut.attach(patcher.patch, for: chat)
        try await eventually { patcher.attempts == 1 }

        sut.clear()
        sut.enqueue(Self.metadata("new visitor"))
        sut.attach(next.patch, for: chat)
        await gate.open()

        try await eventually { next.sent == [Self.metadata("new visitor")] }
        try await Task.sleep(for: .milliseconds(50))
        #expect(next.attempts == 1)
        #expect(patcher.attempts == 1)
    }
}

private extension SessionMetadataQueueTests {

    /// The queue, a patcher and the chat the patcher sends through. The queue holds the chat
    /// weakly, so a test keeps it for as long as that chat is on screen.
    static func makeSUT(
        failures: [Int: ChatServiceError] = [:],
        gate: AsyncGate? = nil
    ) -> (SessionMetadataQueue, ScriptedPatcher, NSObject) {
        (SessionMetadataQueue(), ScriptedPatcher(failures: failures, gate: gate), NSObject())
    }

    static func metadata(_ screen: String) -> SessionMetadataPatchRequest {
        .init(metadata: ["screen": .string(screen)], signedMetadata: nil)
    }

    static func signed(_ token: String) -> SessionMetadataPatchRequest {
        .init(metadata: nil, signedMetadata: token)
    }
}
