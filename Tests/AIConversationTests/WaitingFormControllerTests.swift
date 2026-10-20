//
//  WaitingFormControllerTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// How the waiting-room form loads: retries, a load cleared mid-flight, and forms the card can't
/// show. Fetchers are injected closures; no server is involved.
@Suite("WaitingFormController — loading")
@MainActor
struct WaitingFormControllerTests {

    @Test("a failed load is retried with backoff until the card loads")
    func failedLoadRetries() async throws {
        let attempts = Recorder<Int>()
        let sleeps = Recorder<Duration>()
        let definition = try Self.definition(name: "Waiting")
        let controller = WaitingFormController(
            fetchForm: { _ in
                attempts.record(attempts.count)
                guard attempts.count > 2 else { throw ChatServiceError.transport(.unknown(URLError(.timedOut))) }
                return definition
            },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { sleeps.record($0) }
        )
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)

        try await eventually { controller.model != nil }
        #expect(attempts.count == 3)
        #expect(sleeps.values == [.seconds(2), .seconds(4)])
    }

    @Test("a permanent failure isn't retried during the wait")
    func permanentFailureStops() async throws {
        let fetches = Recorder<String>()
        let controller = WaitingFormController(
            fetchForm: { id in
                fetches.record(id)
                throw ChatServiceError.transport(.http(.unhandled(status: 404, body: Data())))
            },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { _ in }
        )
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)
        try await eventually { fetches.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        controller.statusChanged(to: .waiting)
        try await Task.sleep(for: .milliseconds(20))

        #expect(fetches.count == 1)
        #expect(controller.model == nil)
    }

    @Test("retries pause while the chat is off screen and resume when it's back")
    func retriesPauseOffScreen() async throws {
        let fetches = Recorder<Int>()
        let slept = AsyncGate()
        let wake = AsyncGate()
        let definition = try Self.definition(name: "Waiting")
        let controller = WaitingFormController(
            fetchForm: { _ in
                fetches.record(fetches.count)
                guard fetches.count > 1 else { throw ChatServiceError.transport(.connection(URLError(.timedOut))) }
                return definition
            },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { _ in
                await slept.open()
                await wake.wait()
            }
        )
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)
        await slept.wait()
        controller.setVisible(false)
        await wake.open()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fetches.count == 1)

        controller.setVisible(true)
        try await eventually { controller.model != nil }
        #expect(fetches.count == 2)
    }

    @Test("a retry waiting out its backoff doesn't keep the controller alive")
    func retryDoesNotRetain() async throws {
        let fetches = Recorder<Int>()
        let slept = AsyncGate()
        let wake = AsyncGate()
        weak var released: WaitingFormController?
        do {
            let controller = WaitingFormController(
                fetchForm: { _ in
                    fetches.record(fetches.count)
                    throw ChatServiceError.transport(.connection(URLError(.timedOut)))
                },
                fetchSession: { try Self.emptySession() },
                patchValues: { _, _ in throw CancellationError() },
                sleep: { _ in
                    await slept.open()
                    await wake.wait()
                }
            )
            controller.configure(formId: "livechatWaitingContact")
            controller.statusChanged(to: .waiting)
            released = controller
            await slept.wait()
        }

        try await eventually { released == nil }
        await wake.open()
        try await Task.sleep(for: .milliseconds(20))
        #expect(fetches.count == 1)
    }

    @Test("a load cleared mid-flight never installs its card over the newer one")
    func clearedLoadIsDropped() async throws {
        let gate = AsyncGate()
        let calls = Recorder<Int>()
        let first = try Self.definition(name: "first")
        let second = try Self.definition(name: "second")
        let controller = WaitingFormController(
            fetchForm: { _ in
                calls.record(calls.count)
                guard calls.count == 1 else { return second }
                await gate.wait()
                return first
            },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { _ in throw CancellationError() }
        )
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)
        try await eventually { calls.count == 1 }
        controller.statusChanged(to: .active)
        controller.statusChanged(to: .waiting)
        try await eventually { controller.model?.definition.name == "second" }
        await gate.open()
        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.model?.definition.name == "second")
    }

    @Test("a save the card was cleared during drops its 401, so the new conversation stays")
    func staleSaveExpiryIsDropped() async throws {
        let entered = AsyncGate()
        let release = AsyncGate()
        let expiries = Recorder<Int>()
        let definition = try Self.definition(name: "Waiting")
        let controller = WaitingFormController(
            fetchForm: { _ in definition },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in
                await entered.open()
                await release.wait()
                throw ChatServiceError.sessionExpired
            },
            sleep: { _ in throw CancellationError() }
        )
        controller.bind(onSessionExpired: { expiries.record(1) })
        controller.configure(formId: "livechatWaitingContact")
        controller.statusChanged(to: .waiting)
        try await eventually { controller.model != nil }
        controller.model?.setValue("a@b.com", for: "email")

        let save = Task { await controller.save() }
        await entered.wait()
        controller.clear()
        await release.open()
        await save.value

        #expect(expiries.count == 0)
    }

    @Test("a 409 on save means the visitor is no longer waiting, and drops the card")
    func conflictedSaveDropsCard() async throws {
        let definition = try Self.definition(name: "Waiting")
        let controller = WaitingFormController(
            fetchForm: { _ in definition },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw ChatServiceError.conflict },
            sleep: { _ in throw CancellationError() }
        )
        controller.configure(formId: "livechatWaitingContact")
        controller.statusChanged(to: .waiting)
        try await eventually { controller.model != nil }
        controller.model?.setValue("a@b.com", for: "email")

        await controller.save()

        #expect(controller.model == nil)
    }

    @Test("a session that ended during the first load ends the chat, even when the form read failed too")
    func expiryOutranksFormFailure() async throws {
        let expiries = Recorder<Int>()
        let controller = WaitingFormController(
            fetchForm: { _ in throw ChatServiceError.notFound },
            fetchSession: { throw ChatServiceError.sessionExpired },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { _ in throw CancellationError() }
        )
        controller.bind(onSessionExpired: { expiries.record(1) })
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)

        try await eventually { expiries.count == 1 }
        #expect(controller.model == nil)
    }

    @Test("a form the card can't show isn't fetched again during the same wait")
    func noCardIsRemembered() async throws {
        let fetches = Recorder<String>()
        let fileOnly = try LivechatFixtures.decoder.decode(ChatFormDefinition.self, from: Data(#"""
        {
          "form_id": "livechatWaitingContact",
          "name": null,
          "fields": [{ "key": "photo", "label": "Photo", "type": "file" }],
          "min_filled_fields": 0
        }
        """#.utf8))
        let controller = WaitingFormController(
            fetchForm: { id in
                fetches.record(id)
                return fileOnly
            },
            fetchSession: { try Self.emptySession() },
            patchValues: { _, _ in throw CancellationError() },
            sleep: { _ in throw CancellationError() }
        )
        controller.configure(formId: "livechatWaitingContact")

        controller.statusChanged(to: .waiting)
        try await eventually { fetches.count == 1 }
        try await Task.sleep(for: .milliseconds(20))
        controller.statusChanged(to: .waiting)
        try await Task.sleep(for: .milliseconds(20))

        #expect(fetches.count == 1)
        #expect(controller.model == nil)
    }
}

private extension WaitingFormControllerTests {

    nonisolated static func definition(name: String) throws -> ChatFormDefinition {
        try LivechatFixtures.decoder.decode(ChatFormDefinition.self, from: Data("""
        {
          "form_id": "livechatWaitingContact",
          "name": "\(name)",
          "fields": [{ "key": "email", "label": "Email", "type": "email" }],
          "min_filled_fields": 0
        }
        """.utf8))
    }

    nonisolated static func emptySession() throws -> ChatSessionState {
        try LivechatFixtures.decoder.decode(ChatSessionState.self, from: Data(#"{"values":[]}"#.utf8))
    }
}
