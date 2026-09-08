//
//  ChatViewModelLivechatSessionCallbackTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("ChatView.ViewModel — onLivechatSessionChange")
struct ChatViewModelLivechatSessionCallbackTests {

    @MainActor
    final class CallbackLog {
        private(set) var infos: [AIChat.LivechatSessionInfo] = []
        func append(_ info: AIChat.LivechatSessionInfo) {
            self.infos.append(info)
        }
    }

    @MainActor
    @Test("waiting fires once; identical waiting does not re-fire")
    func waitingDedupe() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(previousStatus: .inactive, state: LivechatState(status: .waiting))
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(previousStatus: .waiting, state: LivechatState(status: .waiting))
        )
        #expect(log.infos.count == 1)
        #expect(log.infos[0].status == .waiting)
        #expect(log.infos[0].agentDisplayName == nil)
    }

    @MainActor
    @Test("waiting then active reports agent name")
    func waitingThenActive() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(previousStatus: .inactive, state: LivechatState(status: .waiting))
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .waiting,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
                )
            )
        )
        #expect(log.infos.map(\.status) == [.waiting, .active])
        #expect(log.infos.last?.agentDisplayName == "Alice")
    }

    @MainActor
    @Test("typing-only tick with same status does not fire")
    func typingDoesNotFire() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .inactive,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice"),
                    isAgentTyping: false
                )
            )
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .active,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice"),
                    isAgentTyping: true
                )
            )
        )
        #expect(log.infos.count == 1)
        #expect(log.infos[0].status == .active)
    }

    @MainActor
    @Test("teardown reports inactive")
    func teardownInactive() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        vm.setLivechatStatusForTesting(.waiting)
        #expect(log.infos.last?.status == .waiting)
        await vm.teardownLivechat()
        #expect(log.infos.last?.status == .inactive)
    }

    @MainActor
    @Test("session-expired snapshot reports inactive after teardown")
    func sessionExpiredInactive() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        vm.setLivechatStatusForTesting(.active, agent: LivechatAgent(agentId: "a", displayName: "Alice"))
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .active,
                state: LivechatState(status: .inactive),
                sessionExpired: true
            )
        )
        #expect(log.infos.map(\.status) == [.active, .inactive])
    }

    @MainActor
    @Test("nil hook does not trap")
    func nilHookSafe() async {
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: nil
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(previousStatus: .inactive, state: LivechatState(status: .waiting))
        )
        await vm.teardownLivechat()
        #expect(vm.livechatStatus == .inactive)
    }

    @MainActor
    @Test("AI 409 resume reports active when livechat is enabled")
    func conflictResumeReportsActive() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            availabilityReason: .alwaysOn
        ))
        vm.setLivechatStatusForTesting(.waiting)
        #expect(log.infos.map(\.status) == [.waiting])
        await vm.resumeLivechatAfterConflict()
        #expect(log.infos.map(\.status) == [.waiting, .active])
        #expect(log.infos.last?.agentDisplayName == nil)
        await vm.teardownLivechat()
    }

    @MainActor
    @Test("AI 409 resume does not report active when livechat is disabled")
    func conflictResumeDisabledDoesNotReport() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        vm.setLivechatStatusForTesting(.waiting)
        #expect(log.infos.map(\.status) == [.waiting])
        await vm.resumeLivechatAfterConflict()
        #expect(log.infos.map(\.status) == [.waiting])
        #expect(vm.livechatStatus == .active)
    }

    @MainActor
    @Test("config apply does not fire the host hook")
    func configDoesNotFire() {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        vm.setLivechatForTesting(LivechatSettings(
            enabled: true,
            configured: true,
            availabilityStatus: .live,
            availabilityReason: .alwaysOn
        ))
        #expect(log.infos.isEmpty)
    }

    @MainActor
    @Test("closed fires once and drops the agent name")
    func closedDropsAgentName() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .waiting,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
                )
            )
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .active,
                state: LivechatState(
                    status: .closed,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
                )
            )
        )
        #expect(log.infos.map(\.status) == [.active, .closed])
        #expect(log.infos.last?.agentDisplayName == nil)
    }

    @MainActor
    @Test("agent rename while active fires once")
    func agentRenameFires() async {
        let log = CallbackLog()
        let vm = ChatView.ViewModel.forTesting(
            provider: StubChatProviding(),
            onLivechatSessionChange: { log.append($0) }
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .inactive,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Alice")
                )
            )
        )
        await vm.applyLivechatSnapshotForTesting(
            LivechatSnapshot(
                previousStatus: .active,
                state: LivechatState(
                    status: .active,
                    activeAgent: LivechatAgent(agentId: "a", displayName: "Bob")
                )
            )
        )
        #expect(log.infos.map(\.agentDisplayName) == ["Alice", "Bob"])
        #expect(log.infos.map(\.status) == [.active, .active])
    }

    @MainActor
    @Test("LivechatSessionInfo strips name when not active")
    func sessionInfoStripsNameWhenNotActive() {
        let info = AIChat.LivechatSessionInfo(status: .waiting, agentDisplayName: "Alice")
        #expect(info.agentDisplayName == nil)
        #expect(info.status == .waiting)
    }

    @MainActor
    @Test("LivechatSessionInfo omits whitespace-only active agent")
    func sessionInfoOmitsBlankActiveAgent() {
        let info = AIChat.LivechatSessionInfo(status: .active, agentDisplayName: "   ")
        #expect(info.agentDisplayName == nil)
        #expect(info.status == .active)
    }
}
