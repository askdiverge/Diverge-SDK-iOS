//
//  AIChatMetadataTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("AIChat — session metadata")
@MainActor
struct AIChatMetadataTests {

    @Test("literals and interpolated strings go out as JSON values; an empty dictionary and a blank token send nothing")
    func setMetadataMapsLiterals() async throws {
        let chat = AIChat(Self.configuration)
        let patcher = ScriptedPatcher(failures: [:], gate: nil)
        let sku = "a1"
        chat.sessionMetadata.attach(patcher.patch, for: chat)

        chat.setMetadata([:])
        chat.setSignedMetadata("  ")
        chat.setMetadata([
            "cseyeStoreSlug": "boozt-se",
            "screen": "product/\(sku)",
            "cart": ["items": 2, "total": 49.5, "skus": ["a1"], "gift": false],
            "coupon": .null
        ])
        chat.setSignedMetadata(" header.claims.signature\n")

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [
            SessionMetadataPatchRequest(
                metadata: [
                    "cseyeStoreSlug": .string("boozt-se"),
                    "screen": .string("product/a1"),
                    "cart": .object([
                        "items": .int(2),
                        "total": .double(49.5),
                        "skus": .array([.string("a1")]),
                        "gift": .bool(false)
                    ]),
                    "coupon": .null
                ],
                signedMetadata: nil
            ),
            SessionMetadataPatchRequest(metadata: nil, signedMetadata: "header.claims.signature")
        ])
    }

    @Test("instances from the shared configuration share one queue; a direct one keeps its own")
    func sharedConfigurationSharesQueue() {
        AIChat.configure(Self.configuration)

        let first = AIChat()
        let second = AIChat()
        let direct = AIChat(Self.configuration)

        #expect(first.sessionMetadata === second.sessionMetadata)
        #expect(direct.sessionMetadata !== first.sessionMetadata)
    }

    @Test("configuring again starts a new queue, so the earlier configuration's metadata stays behind")
    func configuringAgainReplacesQueue() {
        AIChat.configure(Self.configuration)
        let earlier = AIChat()

        AIChat.configure(Self.configuration)

        #expect(AIChat().sessionMetadata !== earlier.sessionMetadata)
    }

    @Test("a send goes at once while metadata is on its way")
    func sendDoesNotWaitForMetadata() async throws {
        let gate = AsyncGate()
        let patcher = ScriptedPatcher(failures: [:], gate: gate)
        let (viewModel, queue, provider) = Self.makeViewModel(patcher: patcher)
        await viewModel.setVisible(true)
        queue.enqueue(Self.screen("checkout"))
        try await eventually { patcher.attempts == 1 }
        viewModel.currentMessage = "Where is my order?"

        try await viewModel.send()

        #expect(provider.lastSent == "Where is my order?")
        #expect(patcher.sent.isEmpty)
        await gate.open()
        try await eventually { patcher.sent == [Self.screen("checkout")] }
    }

    @Test("a send sends again the metadata a failure left queued")
    func sendRetriesQueuedMetadata() async throws {
        let failed = ChatServiceError.transport(.connection(URLError(.notConnectedToInternet)))
        let patcher = ScriptedPatcher(failures: [0: failed], gate: nil)
        let (viewModel, queue, _) = Self.makeViewModel(patcher: patcher)
        await viewModel.setVisible(true)
        queue.enqueue(Self.screen("checkout"))
        try await eventually { patcher.attempts == 1 }
        viewModel.currentMessage = "Where is my order?"

        try await viewModel.send()

        try await eventually { patcher.sent == [Self.screen("checkout")] }
        #expect(patcher.attempts == 2)
    }

    @Test("metadata waits while the chat is off screen and goes when it is back")
    func offScreenChatHoldsMetadata() async throws {
        let patcher = ScriptedPatcher(failures: [:], gate: nil)
        let (viewModel, queue, _) = Self.makeViewModel(patcher: patcher)
        await viewModel.setVisible(true)
        queue.enqueue(Self.screen("home"))
        try await eventually { patcher.sent.count == 1 }

        await viewModel.setVisible(false)
        queue.enqueue(Self.screen("product"))
        queue.enqueue(Self.screen("checkout"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(patcher.attempts == 1)

        await viewModel.setVisible(true)

        try await eventually { patcher.sent.count == 2 }
        #expect(patcher.sent == [Self.screen("home"), Self.screen("checkout")])
    }

    @Test("deleting the visitor's data drops metadata still queued")
    func deleteClearsQueue() async throws {
        let failed = ChatServiceError.transport(.connection(URLError(.notConnectedToInternet)))
        let patcher = ScriptedPatcher(failures: [0: failed], gate: nil)
        let (viewModel, queue, _) = Self.makeViewModel(patcher: patcher)
        queue.enqueue(Self.screen("account"))
        await viewModel.setVisible(true)
        try await eventually { patcher.attempts == 1 }

        try await viewModel.delete()
        await viewModel.setVisible(true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(patcher.attempts == 1)
        #expect(patcher.sent.isEmpty)
    }

    @Test("metadata set while the visitor's data is being deleted is dropped with it, unsent")
    func metadataSetDuringDeleteIsDropped() async throws {
        let patcher = ScriptedPatcher(failures: [:], gate: nil)
        let (viewModel, queue, provider) = Self.makeViewModel(patcher: patcher)
        await viewModel.setVisible(true)
        provider.whileDeleting = {
            queue.enqueue(Self.screen("account"))
            try? await Task.sleep(for: .milliseconds(50))
        }

        try await viewModel.delete()
        await viewModel.setVisible(true)
        try await Task.sleep(for: .milliseconds(50))

        #expect(patcher.attempts == 0)
    }

    @Test("a delete that fails sends the metadata set during it")
    func failedDeleteKeepsSending() async throws {
        let patcher = ScriptedPatcher(failures: [:], gate: nil)
        let (viewModel, queue, provider) = Self.makeViewModel(patcher: patcher)
        await viewModel.setVisible(true)
        provider.deleteError = URLError(.notConnectedToInternet)
        provider.whileDeleting = { queue.enqueue(Self.screen("account")) }

        await #expect(throws: ChatView.DeletionFailed.self) { try await viewModel.delete() }

        try await eventually { patcher.sent == [Self.screen("account")] }
    }
}

private extension AIChatMetadataTests {

    static let configuration = AIChat.Configuration(
        tokenProvider: { "token" },
        resetConversation: { "token" },
        deleteData: {}
    )

    /// A view model with a stub provider attached, sending metadata from `queue` through `patcher`.
    static func makeViewModel(
        patcher: ScriptedPatcher
    ) -> (ChatView.ViewModel, SessionMetadataQueue, StubChatProviding) {
        let queue = SessionMetadataQueue()
        let provider = StubChatProviding()
        let viewModel = ChatView.ViewModel.forTesting(
            provider: provider,
            sessionMetadata: queue,
            patchSessionMetadata: patcher.patch
        )
        return (viewModel, queue, provider)
    }

    static func screen(_ name: String) -> SessionMetadataPatchRequest {
        .init(metadata: ["screen": .string(name)], signedMetadata: nil)
    }
}
