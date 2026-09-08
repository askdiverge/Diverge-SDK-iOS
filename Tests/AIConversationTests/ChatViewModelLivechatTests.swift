//
//  ChatViewModelLivechatTests.swift
//  AIConversationTests
//

import Foundation
import Testing
import SwiftUI
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — livechat send routing")
struct ChatViewModelLivechatTests {

    @MainActor
    @Test("inactive / waiting / closed route to AI send; active routes to livechat")
    func sendRoutingByStatus() async throws {
        for status in [LivechatState.Status.inactive, .waiting, .closed] {
            let provider = StubChatProviding()
            let vm = ChatView.ViewModel.forTesting(provider: provider)
            vm.setLivechatStatusForTesting(status)
            vm.currentMessage = "hello \(status.rawValue)"
            try await vm.send()
            #expect(provider.lastSent == "hello \(status.rawValue)")
            #expect(provider.lastLivechatSent == nil)
        }

        let activeProvider = StubChatProviding()
        let activeVM = ChatView.ViewModel.forTesting(provider: activeProvider)
        activeVM.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        activeVM.currentMessage = "hi agent"
        try await activeVM.send()
        #expect(activeProvider.lastLivechatSent == "hi agent")
        #expect(activeProvider.lastSent == nil)
    }

    @MainActor
    @Test("409 conflict re-routes to livechat send")
    func conflictReroutes() async throws {
        let provider = StubChatProviding(sendFailure: .conflict(popped: "race"))
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatStatusForTesting(.waiting)
        vm.currentMessage = "race"
        try await vm.send()
        #expect(provider.lastLivechatSent == "race")
        #expect(vm.livechatStatus == .active)
    }

    @MainActor
    @Test("livechat-send 409 re-routes to the AI path")
    func livechatInactiveReroutesToAI() async throws {
        let provider = StubChatProviding()
        provider.livechatSendFailure = .livechatInactive(popped: "bye")
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatStatusForTesting(.active)
        vm.currentMessage = "bye"
        try await vm.send()
        #expect(provider.lastSent == "bye")
    }

    @MainActor
    @Test("applyLivechatFromConfig mirrors availability")
    func applyConfig() {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            availabilityReason: .alwaysOn
        ))
        #expect(vm.livechatEnabled)
        #expect(vm.livechatAvailable)
        #expect(vm.inputPlaceholder == L10n.inputPlaceholder.string)
        vm.setLivechatStatusForTesting(.waiting)
        #expect(vm.inputPlaceholder == L10n.livechatWaitingPlaceholder.string)
    }

    @MainActor
    @Test("transition notes mint once per edge")
    func transitionNotes() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)

        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(status: .waiting)
        ))
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .waiting,
            state: LivechatState(
                status: .active,
                activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
            )
        ))
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .active,
            state: LivechatState(status: .closed)
        ))
        // Repeat closed — no extra ended note.
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .closed,
            state: LivechatState(status: .closed)
        ))

        #expect(provider.notes.map(\.kind) == [
            .queued,
            .agentJoined(displayName: "Alice"),
            .ended,
        ])
    }

    @MainActor
    @Test("stale closed snapshot after local close does not remint ended")
    func staleSnapshotAfterClose() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .active,
            state: LivechatState(status: .closed)
        ))
        #expect(provider.notes.map(\.kind) == [.ended])
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .closed,
            state: LivechatState(status: .closed)
        ))
        #expect(provider.notes.map(\.kind) == [.ended])
    }

    @MainActor
    @Test("rehydration into active mints agent-joined, not queued")
    func rehydrateActive() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .inactive,
            state: LivechatState(
                status: .active,
                activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
            )
        ))
        #expect(provider.notes.map(\.kind) == [.agentJoined(displayName: "Alice")])
    }

    @MainActor
    @Test("expiry resets the mirror and expires the provider")
    func expiryResetsMirror() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .active,
            state: LivechatState(status: .inactive),
            sessionExpired: true
        ))
        #expect(vm.livechatStatus == .inactive)
        #expect(vm.livechatSessionEnded)
        #expect(vm.activeAgent == nil)
    }

    @MainActor
    @Test("typing posts true once per burst")
    func typingOncePerBurst() {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        vm.visitorTypingChanged(isEmpty: false)
        vm.visitorTypingChanged(isEmpty: false)
        vm.visitorTypingChanged(isEmpty: false)
        #expect(vm.typingPosts == [true])
        vm.visitorTypingChanged(isEmpty: true)
        #expect(vm.typingPosts == [true, false])
    }

    @MainActor
    @Test("host attachments.disabled wins over livechat attachments_enabled")
    func hostDisabledWinsOverLivechatAttach() {
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            attachments: .disabled
        )
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            attachmentsEnabled: true
        ))
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        #expect(vm.canAttach == false)
        #expect(vm.canAttachConsideringLivechat == false)
    }

    @MainActor
    @Test("pending attachments drop when active and attachments_enabled is false")
    func dropAttachmentsOnActiveWhenDisabled() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatForTesting(LivechatSettings(enabled: true, configured: true, attachmentsEnabled: false))
        vm.pendingAttachments = [
            PendingAttachment(
                thumbnail: .init(systemName: "photo"),
                attachment: OutgoingAttachment(kind: .image, data: "YQ==", mime: "image/jpeg"),
                displayName: "photo"
            )
        ]
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .waiting,
            state: LivechatState(status: .active)
        ))
        #expect(vm.pendingAttachments.isEmpty)
        #expect(vm.canAttachConsideringLivechat == false)
    }

    @MainActor
    @Test("pending attachments stay when active and attachments_enabled is true")
    func keepAttachmentsOnActiveWhenEnabled() async {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            attachmentsEnabled: true
        ))
        vm.pendingAttachments = [
            PendingAttachment(
                thumbnail: .init(systemName: "photo"),
                attachment: OutgoingAttachment(kind: .image, data: "YQ==", mime: "image/jpeg"),
                displayName: "photo"
            )
        ]
        await vm.applyLivechatSnapshotForTesting(LivechatSnapshot(
            previousStatus: .waiting,
            state: LivechatState(
                status: .active,
                activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
            )
        ))
        #expect(vm.pendingAttachments.count == 1)
        #expect(vm.canAttachConsideringLivechat == true)
    }

    @MainActor
    @Test("waiting still allows AI attach regardless of attachments_enabled")
    func waitingAllowsAttach() {
        let provider = StubChatProviding()
        let vm = ChatView.ViewModel.forTesting(provider: provider)
        vm.setLivechatForTesting(LivechatSettings(enabled: true, configured: true, attachmentsEnabled: false))
        vm.setLivechatStatusForTesting(.waiting)
        #expect(vm.canAttachConsideringLivechat == true)
    }

    @MainActor
    @Test("waiting + attachments_enabled passes a tighter max_attachment_size_bytes into the encoder")
    func waitingUsesLivechatEncodeCapWhenEnabled() async {
        let box = CapBox()
        let vm = Self.makeCapVM(box: box)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            attachmentsEnabled: true,
            maxAttachmentSizeBytes: 3_000
        ))
        vm.setLivechatStatusForTesting(.waiting)
        await vm.ingestPickedPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(box.maxEncodedLength == 4_000)
    }

    @MainActor
    @Test("waiting + attachments_enabled false keeps the default chat encode cap")
    func waitingKeepsChatCapWhenLivechatAttachDisabled() async {
        let box = CapBox()
        let vm = Self.makeCapVM(box: box)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            attachmentsEnabled: false,
            maxAttachmentSizeBytes: 3_000
        ))
        vm.setLivechatStatusForTesting(.waiting)
        await vm.ingestPickedPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(box.maxEncodedLength == OutgoingAttachment.maxEncodedLength)
    }

    @MainActor
    @Test("active livechat passes a tighter max_attachment_size_bytes into the encoder")
    func activeUsesLivechatEncodeCap() async {
        let box = CapBox()
        let vm = Self.makeCapVM(box: box)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            attachmentsEnabled: true,
            maxAttachmentSizeBytes: 3_000
        ))
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        await vm.ingestPickedPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(box.maxEncodedLength == 4_000)
    }

    @MainActor
    @Test("default 5 MiB livechat budget does not rewrite the chat encode cap")
    func defaultLivechatBudgetDoesNotTighten() async {
        let box = CapBox()
        let vm = Self.makeCapVM(box: box)
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            attachmentsEnabled: true,
            maxAttachmentSizeBytes: 5_242_880
        ))
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        await vm.ingestPickedPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(box.maxEncodedLength == OutgoingAttachment.maxEncodedLength)
    }

    @MainActor
    @Test("requestHandover POST includes truncated contextProvider page")
    func requestHandoverSendsPageInClientContext() async throws {
        let waitingState = Data(#"""
        {
          "status": "waiting",
          "active_agent": null,
          "is_agent_typing": false,
          "agent_joined_at": null,
          "closed_by": null,
          "feedback": { "status": "not_available", "submitted_at": null }
        }
        """#.utf8)
        let emptyMessages = Data(#"{"messages":[],"has_more":false}"#.utf8)
        var responses: [ScriptedURLProtocol.Response] = [
            .init(status: 200, body: Data(#"{"status":"waiting"}"#.utf8)),
            .init(status: 200, body: waitingState),
            .init(status: 200, body: emptyMessages)
        ]
        for _ in 0..<4 {
            responses.append(.init(status: 200, body: waitingState))
            responses.append(.init(status: 200, body: emptyMessages))
        }
        let page = String(repeating: "p", count: 2100)
        let (service, script) = ChatServiceFixtures.makeSUT(responses: responses)
        let viewModel = ChatView.ViewModel(
            service: service,
            contextProvider: { page },
            conversationFlow: .topDown,
            submittedForms: SubmittedFormStore(fileURL: nil)
        )
        viewModel.attachProviderForTesting(StubChatProviding())

        try await viewModel.requestHandover(source: LivechatHandoverRequest.manualButtonSource)

        let handover = try #require(script.requests.first { $0.url?.path().contains("handover") == true })
        let ctx = try #require(handover.json?["client_context"] as? [String: Any])
        let url = try #require(ctx["current_page_url"] as? String)
        #expect(url.count == 2048)
        #expect(url == String(repeating: "p", count: 2048))
        #expect(ctx["os"] as? String == "iOS" || ctx["os"] as? String == "macOS")
        await viewModel.teardownLivechat()
    }

    private final class CapBox: @unchecked Sendable {
        var maxEncodedLength: Int?
    }

    @MainActor
    private static func makeCapVM(box: CapBox) -> ChatView.ViewModel {
        ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            encodeAttachment: { data, options throws(ImageAttachment.Failure) in
                box.maxEncodedLength = options.maxEncodedLength
                return try ImageAttachment.encode(data, options: options)
            }
        )
    }
}
