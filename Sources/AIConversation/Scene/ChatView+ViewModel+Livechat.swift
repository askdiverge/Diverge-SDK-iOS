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

    /// The composer placeholder, naming who the next message goes to.
    var inputPlaceholder: String {
        switch self.livechatStatus {
        case .waiting: L10n.livechatWaitingPlaceholder.string
        case .active: L10n.livechatActivePlaceholder.string
        case .closed: L10n.livechatClosedPlaceholder.string
        case .inactive, .unknown: L10n.inputPlaceholder.string
        }
    }

    /// Pauses livechat polling while the app is in the background.
    func setSceneActive(_ active: Bool) async {
        await self.livechat.setSceneActive(active)
    }

    /// Pauses livechat polling while the chat is off screen.
    func setVisible(_ visible: Bool) async {
        await self.livechat.setVisible(visible)
    }

    /// Queues the visitor for an agent with the native client context.
    func requestLivechat() async {
        let context = LivechatClientContext.native(page: await self.pageContext())
        do {
            try await self.livechat.handover(source: .manualButton, partId: nil, clientContext: context)
        } catch .conflict {
            self.presentLivechatNotice(L10n.livechatOffline)
        } catch .sessionExpired {
            // The session's snapshot ends the chat.
        } catch {
            self.presentLivechatNotice(L10n.noticeSendFailed)
        }
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
