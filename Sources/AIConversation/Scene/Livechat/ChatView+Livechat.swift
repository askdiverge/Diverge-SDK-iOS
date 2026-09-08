//
//  ChatView+Livechat.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

extension ChatView.ViewModel {

    /// Livechat session status mirrored from the poller.
    var livechatStatus: LivechatState.Status { self.livechat.status }

    /// Active agent identity when the session is `active`.
    var activeAgent: LivechatAgent? { self.livechat.activeAgent }

    /// Whether the agent is currently typing.
    var isAgentTyping: Bool { self.livechat.isAgentTyping }

    /// Whether livechat is configured enabled (toolbar / marker gate).
    var livechatEnabled: Bool { self.livechat.enabled }

    /// Whether handovers are currently accepted (`enabled` + `live`).
    var livechatAvailable: Bool { self.livechat.available }

    /// Whether the header livechat control should show when idle.
    var showLivechatLogo: Bool { self.livechat.showLogo }

    /// Whether the visitor is waiting or chatting with an agent.
    var isLivechatInSession: Bool { self.livechat.isInSession }

    /// Poller saw a 401 — the view presents the existing session-ended alert.
    var livechatSessionEnded: Bool { self.livechat.sessionEnded }

    /// Composer placeholder for the current livechat status.
    var inputPlaceholder: String {
        switch self.livechat.status {
        case .waiting:
            return L10n.livechatWaitingPlaceholder.string
        case .active:
            return L10n.livechatAgentPlaceholder(self.livechat.agentDisplayName).string
        default:
            return L10n.inputPlaceholder.string
        }
    }

    /// Composer / upload-prompt attach gate. Waiting keeps the AI path; active requires
    /// `/config` `livechat.attachments_enabled` (host `.disabled` still wins via `canAttach`).
    var canAttachConsideringLivechat: Bool {
        guard self.canAttach else { return false }
        if self.livechat.status == .active {
            return self.livechat.attachmentsEnabled
        }
        return true
    }

    /// Copies livechat settings from `/config`.
    func applyLivechatFromConfig(_ settings: LivechatSettings) {
        self.livechat.apply(settings: settings)
    }

    /// Test seam — sets livechat config without going through `/config`.
    func setLivechatForTesting(_ settings: LivechatSettings) {
        self.applyLivechatFromConfig(settings)
    }

    /// Test seam — mirrors a livechat status without the poller.
    func setLivechatStatusForTesting(_ status: LivechatState.Status, agent: LivechatAgent? = nil) {
        self.livechat.markStatus(status, agent: agent)
        self.reportLivechatSessionIfChanged()
    }

    /// Test seam — drives the same path the poller uses so note minting is unit-testable.
    func applyLivechatSnapshotForTesting(_ snapshot: LivechatSnapshot) async {
        await self.applyLivechatSnapshot(snapshot)
    }

    /// Maps mirror state onto the public host payload and fires when it changed.
    func reportLivechatSessionIfChanged() {
        let info = self.makeLivechatSessionInfo()
        guard info != self.lastReportedLivechatSession else { return }
        self.lastReportedLivechatSession = info
        self.onLivechatSessionChange?(info)
    }

    /// Public ``AIChat/LivechatSessionInfo`` from the current mirror (no package types).
    func makeLivechatSessionInfo() -> AIChat.LivechatSessionInfo {
        let status: AIChat.LivechatSessionInfo.Status
        switch self.livechat.status {
        case .waiting: status = .waiting
        case .active: status = .active
        case .closed: status = .closed
        case .inactive, .unknown: status = .inactive
        }
        let name = status == .active ? self.livechat.activeAgent?.displayName : nil
        return AIChat.LivechatSessionInfo(status: status, agentDisplayName: name)
    }

    /// Requests handover. `source` is `manual_button` or `assistant_marker`.
    /// Notes are minted from the poller's `(previous, current)` — not here.
    func requestHandover(source: String, partId: String? = nil) async throws(ChatView.SessionEnded) {
        guard !self.isLivechatCSATBlockingHandover else { return }
        do {
            let session = self.ensureLivechatSession()
            self.observeLivechat(session)
            let page = await self.pageContext()
            try await session.handover(
                source: source,
                partId: partId,
                clientContext: LivechatClientContext.native(page: page)
            )
        } catch ChatServiceError.sessionExpired {
            throw ChatView.SessionEnded()
        } catch ChatServiceError.conflict {
            self.presentLivechatNotice(L10n.livechatOffline.string, edge: .top)
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed.string, edge: .bottom)
        }
    }

    /// Visitor leaves the queue or ends an active chat.
    func closeLivechat(reason: String?) async throws(ChatView.SessionEnded) {
        do {
            let session = self.ensureLivechatSession()
            try await session.close(reason: reason)
            self.endTypingIfNeeded()
        } catch ChatServiceError.sessionExpired {
            throw ChatView.SessionEnded()
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed.string, edge: .bottom)
        }
    }

    /// Debounced visitor typing — posts `true` once per burst, `false` after 1.5 s idle. Active only.
    func visitorTypingChanged(isEmpty: Bool) {
        self.typingIdleTask?.cancel()
        guard self.livechat.status == .active else {
            self.endTypingIfNeeded()
            return
        }
        if isEmpty {
            self.endTypingIfNeeded()
            return
        }
        if !self.isTypingSent {
            self.isTypingSent = true
            self.postTyping(true)
        }
        self.typingIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.endTypingIfNeeded()
        }
    }

    /// Scene-phase gate for the livechat poller.
    func setLivechatSceneActive(_ active: Bool) {
        Task { await self.livechatSession?.setSceneActive(active) }
    }

    /// On-screen gate — the poller parks when `ChatView` leaves the hierarchy.
    func setLivechatVisible(_ visible: Bool) {
        Task { await self.livechatSession?.setVisible(visible) }
    }

    /// Boots the livechat poller when config enables it (rehydration on relaunch).
    func bootstrapLivechatIfNeeded() async {
        guard self.livechat.enabled else { return }
        _ = await self.attachPollerAndBootstrap()
    }

    /// Stops the poller and resets mirrored status. Called from reset / delete / expiry.
    func teardownLivechat() async {
        self.endTypingIfNeeded()
        if let session = self.livechatSession {
            await session.teardown()
        }
        self.livechat.reset()
        self.clearWaitingForm()
        self.reportLivechatSessionIfChanged()
    }

    /// A 409 on the AI path revealed an active session — start polling if livechat is enabled.
    /// Status is marked `.active` even when `/config` has livechat off (send routing); the host
    /// hook only fires when we will actually attach the poller, so a stale disabled flag cannot
    /// leave a stuck `.active` badge.
    func resumeLivechatAfterConflict() async {
        self.livechat.markStatus(.active)
        guard self.livechat.enabled else { return }
        self.reportLivechatSessionIfChanged()
        let session = self.ensureLivechatSession()
        self.observeLivechat(session)
        await session.resumeActive()
    }

    /// Livechat send 409: session closed between polls — refresh state then send on the AI path.
    func rerouteToAIAfterLivechatInactive(
        _ text: String,
        attachments: [OutgoingAttachment],
        provider: any ChatProviding
    ) async throws(ChatView.SessionEnded) -> String? {
        await self.livechatSession?.refresh()
        self.endTypingIfNeeded()
        do {
            try await provider.send(text, attachments: attachments)
            return nil
        } catch {
            switch error {
            case .sessionExpired:
                throw ChatView.SessionEnded()
            case .busy(.streaming):
                self.presentNotice(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))
                return text
            case .busy(.operation):
                return text
            case .retry(popped: let lastMessage, body: let body):
                self.presentNotice(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))
                return lastMessage
            case .conflict(popped: let popped):
                // Flipped back to active while we were re-routing. Try livechat once more.
                await self.resumeLivechatAfterConflict()
                do {
                    try await provider.sendLivechat(popped, attachments: attachments)
                    return nil
                } catch {
                    self.presentNotice(Notice(
                        edge: .bottom,
                        message: L10n.noticeSendFailed.string,
                        autoDismiss: nil
                    ))
                    return popped
                }
            case .livechatInactive(popped: let popped):
                self.presentNotice(Notice(
                    edge: .bottom,
                    message: L10n.noticeSendFailed.string,
                    autoDismiss: nil
                ))
                return popped
            }
        }
    }

    /// After `POST /actions` created a waiting/active session via `start_livechat` — attach the
    /// poller without calling handover (the server already owns the session row).
    /// Confirmation stays either way. Transport / idle GET `/state` surfaces the send-failed
    /// notice so “Connecting…” is not a silent dead end. 401 uses the session-ended alert.
    func adoptLivechatSessionAfterFormSubmit() async {
        let outcome = await self.attachPollerAndBootstrap()
        if case .notInSession = outcome {
            self.presentLivechatNotice(L10n.noticeSendFailed.string, edge: .bottom)
        }
    }

    /// Shared poller attach + `GET /state`. Config path keeps the `enabled` guard; form adopt
    /// skips it because the server already created the session.
    func attachPollerAndBootstrap() async -> LivechatBootstrapOutcome {
        let session = self.ensureLivechatSession()
        self.observeLivechat(session)
        return await session.bootstrap()
    }

    fileprivate func ensureLivechatSession() -> LivechatSession {
        if let existing = self.livechatSession { return existing }
        let session = LivechatSession(service: self.service)
        self.livechatSession = session
        return session
    }

    fileprivate func observeLivechat(_ session: LivechatSession) {
        guard !self.livechatObserveStarted else { return }
        self.livechatObserveStarted = true
        let stream = session.stream
        Task { [weak self] in
            for await snapshot in stream {
                await self?.applyLivechatSnapshot(snapshot)
            }
        }
    }

    fileprivate func applyLivechatSnapshot(_ snapshot: LivechatSnapshot) async {
        if snapshot.sessionExpired {
            await self.provider?.expireSession()
            await self.teardownLivechat()
            self.livechat.markSessionEnded()
            return
        }

        let previous = snapshot.previousStatus
        let status = snapshot.state.status
        let becameActive = previous != .active && status == .active

        if status == .waiting || status == .active {
            self.resetLivechatCSATDismiss()
        }

        self.livechat.apply(snapshot: snapshot)
        self.reportLivechatSessionIfChanged()
        self.updateWaitingFormForStatusChange(previous: previous, status: status)

        if previous != .waiting, status == .waiting {
            await self.provider?.note(LivechatNote(kind: .queued))
        }
        if becameActive {
            let name = self.livechat.agentDisplayName
            await self.provider?.note(LivechatNote(kind: .agentJoined(displayName: name)))
            // Keep pending chips when the agent session accepts attachments so the visitor
            // can send a photo picked while waiting; otherwise drop with a notice.
            if !self.livechat.attachmentsEnabled {
                self.dropPendingAttachmentsForLivechat()
            }
        }
        if previous.isInSession, status == .closed {
            await self.provider?.note(LivechatNote(kind: .ended))
            self.endTypingIfNeeded()
        }
        if status == .closed {
            self.offerLivechatCSATIfNeeded(
                feedbackPending: snapshot.state.feedback.status == .pending
            )
        }

        if !snapshot.messages.isEmpty {
            await self.provider?.appendLivechat(snapshot.messages)
        }
    }

    func endTypingIfNeeded() {
        self.typingIdleTask?.cancel()
        self.typingIdleTask = nil
        guard self.isTypingSent else { return }
        self.isTypingSent = false
        self.postTyping(false)
    }

    func postTyping(_ isTyping: Bool) {
        self.typingPosts.append(isTyping)
        guard !self.suppressLivechatNetwork else { return }
        Task { try? await self.service.sendLivechatTyping(isTyping: isTyping) }
    }

    func dropPendingAttachmentsForLivechat() {
        guard !self.pendingAttachments.isEmpty else { return }
        self.pendingAttachments = []
        self.presentNotice(Notice(
            edge: .bottom,
            message: L10n.livechatAttachmentsDropped.string,
            autoDismiss: .seconds(4)
        ))
    }

    fileprivate func presentLivechatNotice(_ message: String, edge: Notice.Edge) {
        self.presentNotice(Notice(edge: edge, message: message, autoDismiss: .seconds(4)))
    }
}
