//
//  ChatView+ViewModel+Livechat.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

extension ChatView.ViewModel {

    /// What the header livechat control offers. It shows only while livechat is enabled with its
    /// logo, and always during a session so the visitor can end it.
    enum LivechatControl {
        case hidden, start, end, offline
    }

    var livechatControl: LivechatControl {
        if self.livechatStatus.isInSession { return .end }
        guard self.livechatConfig.enabled, self.livechatConfig.showLivechatLogo else { return .hidden }
        return self.livechatConfig.isAvailable ? .start : .offline
    }

    /// A reply is sending or streaming. A handover waits for it: the agent's context is copied when
    /// the session opens, so a reply still in flight would never reach the agent.
    var isReplyInFlight: Bool {
        self.isSending || self.snapshot?.streamingTurnID != nil
    }

    /// The header control waits while a handover or close is in flight, and offers a handover only
    /// once no reply is in flight.
    var isLivechatControlEnabled: Bool {
        !self.isLivechatBusy && (self.livechatControl == .end || !self.isReplyInFlight)
    }

    /// The composer placeholder, naming who the next message goes to.
    var inputPlaceholder: String {
        switch self.livechatStatus {
        case .waiting: L10n.livechatWaitingPlaceholder.string
        case .active: L10n.livechatActivePlaceholder.string
        case .closed: L10n.livechatClosedPlaceholder.string
        case .inactive, .unknown: L10n.inputPlaceholder.string
        }
    }

    /// Pauses livechat polling and waiting-form retries while the app is in the background; the
    /// rating prompt and the host's updates wait for it to be active again.
    func setSceneActive(_ active: Bool) async {
        self.isSceneActive = active
        self.screenChanged()
        self.waitingForm.setSceneActive(active)
        await self.livechat.setSceneActive(active)
    }

    /// Pauses livechat polling and waiting-form retries while the chat is off screen; the rating
    /// prompt and the host's updates wait for it to be back.
    func setVisible(_ visible: Bool) async {
        self.isChatVisible = visible
        self.screenChanged()
        self.waitingForm.setVisible(visible)
        await self.livechat.setVisible(visible)
    }

    /// Queues the visitor for an agent with the native client context, once no reply is in flight.
    /// Pass `partId` when the request comes from a `request_human_agent` marker so the API can
    /// attribute the handover.
    func requestLivechat(partId: String? = nil) async {
        guard !self.isReplyInFlight else { return }
        let epoch = self.livechatEpoch
        let context = LivechatClientContext.native(page: await self.pageContext())
        // A delete while the host's callback ran replaced the visitor; nothing is handed over.
        guard epoch == self.livechatEpoch else { return }
        let source: LivechatHandoverRequest.Source = partId == nil ? .manualButton : .assistantMarker
        do {
            try await self.livechat.handover(source: source, partId: partId, clientContext: context)
        } catch .conflict {
            self.presentLivechatNotice(L10n.livechatOffline)
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed)
        }
    }

    /// The visitor edited the draft. While an agent is connected, the session tells the agent
    /// they are typing; the view model's own writes to ``currentMessage`` report nothing.
    func editDraft(_ text: String) {
        self.currentMessage = text
        guard self.livechatStatus == .active else { return }
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Task { [livechat = self.livechat] in await livechat.visitorTyping(isEmpty: isEmpty) }
    }

    /// Whether the `request_human_agent` card in bot turn `turnID` can hand over: it is in the
    /// newest bot turn, like a fillable form, no session is open, nothing is in flight and the
    /// reply it came in has finished.
    func canAcceptHumanAgentPrompt(inBotTurn turnID: UUID) -> Bool {
        self.isFormEditable(inBotTurn: turnID) && !self.livechatStatus.isInSession && !self.isLivechatBusy
            && !self.isReplyInFlight
    }

    /// The link to open for `file`, or nil when there is none. A temporary signed link is re-read
    /// from the livechat log on every tap, so a link past its expiry still opens. When the log
    /// can't supply one, a stored link that hasn't expired is opened and the server serves or
    /// refuses it; an expired one is nil, since the server refuses it. A tap whose task was
    /// cancelled, because the chat closed while the log was read, is nil too.
    func url(toOpen file: MessageFile) async -> URL? {
        guard file.urlExpiresAt != nil, let id = file.attachmentId else { return file.url }
        let fresh = await self.livechat.freshFile(attachmentId: id)
        guard !Task.isCancelled else { return nil }
        if let fresh {
            return fresh.url
        }
        return file.isExpired() ? nil : file.url
    }

    /// Ends the session from the visitor's side.
    func endLivechat() async {
        do {
            try await self.livechat.close(reason: LivechatCloseRequest.endedByVisitorReason)
        } catch .conflict {
            // Nothing is open on the server; read what is.
            await self.livechat.refresh()
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed)
        }
    }

    /// Sends to the agent while a session is active, otherwise to the assistant. A 409 on the
    /// assistant send has the session read: the text goes to the agent when one is active, and is
    /// offered for retry otherwise.
    func deliver(_ text: String, via provider: any ChatProviding) async throws(ChatProvider.SendFailure) {
        guard self.livechatStatus != .active else {
            try await provider.sendLivechat(text)
            return
        }
        do {
            try await provider.send(text)
        } catch .livechatActive(let popped) {
            guard await self.livechat.resumeActive() else { throw .retry(popped: popped, body: nil) }
            try await provider.sendLivechat(popped)
        }
    }
}
