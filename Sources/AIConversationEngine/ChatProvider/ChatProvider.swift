//
//  ChatProvider.swift
//  AIConversationEngine
//
//  Created by Daniel Wennberg on 2026-06-11.
//

import Foundation
import AIConversationCore

/// Stateful session data layer between the facade (`ChatServicing`, pure wire I/O)
/// and the view model.
/// Owns the conversation and the streaming lifecycle.
package actor ChatProvider: ChatProviding {

    package typealias ChatStream = AsyncStream<ConversationSnapshot>

    let service: any ChatServicing
    let pageContext: @Sendable () async -> String?

    /// yield new chat conversations
    private let continuation: ChatStream.Continuation

    /// Synthetic greeting from config — a plain string, wrapped into a `ChatResponse`
    /// each time the conversation is published. See ``welcome``.
    private let welcomeMessage: String?

    /// The turn that carries the greeting, whichever pane leads the conversation.
    private let welcomeTurnID = UUID()

    /// Whether `request_image_upload` markers render. Off when the host disabled attachments.
    let acceptsImageUploadPrompts: Bool

    /// Right pane — committed user turns. Outer = turns, inner = adjacent bubbles
    /// (text, and the attachments of a send from this device).
    var user: [Identified<[UserContent]>] = []

    /// Left pane — committed turns from every non-user role (assistant, agent,
    /// system) folded together, as display models.
    var incoming: [Identified<[ChatResponse]>] = []

    /// Owns the history cursor and serializes pagination — no overlapping loads.
    private var paginator = Paginator()

    /// The turn whose reply is streaming
    /// and the marker the snapshot carries so the view can flag that a turn is live.
    /// Set before the first suspension in `send`, cleared when the stream settles.
    var streamingTurnID: UUID?

    /// The bot turns whose replies a send streamed, for the snapshot's `liveTurnIDs`.
    var liveTurnIDs: Set<UUID> = []

    /// Serializes send/reset/delete — they must not interleave.
    var isBusy = false

    /// Message ids already in the panes, from history, the livechat log and this device's sends,
    /// so the poller's copy of a message isn't shown twice.
    var livechatMessageIDs: Set<String> = []
    /// The newest `created_at` of the first history page, in milliseconds. History carries every
    /// livechat message stored before it was read, under ids of its own, so the log's copies up
    /// to this point are already on screen.
    var historyHead: Int64?
    /// Which pane holds the conversation's first turn. Turns pair up by index across the panes,
    /// leading pane first; whatever opens an empty conversation sets it, and so does each
    /// history page.
    var botLeads = false
    /// Livechat messages and notes that arrived while an operation was in flight, in arrival
    /// order. A streaming reply owns the newest bot turn, and a livechat send's id isn't known
    /// until its POST returns, so they are folded in when the operation finishes.
    var deferredLivechat: [DeferredLivechat] = []
    /// Set when a call outside the operation — the poller, a form submit, a history page — saw the
    /// session end while it ran; the conversation clears when the operation finishes, so a
    /// streaming reply never writes into emptied panes.
    var expiresAfterOperation = false
    /// A livechat message whose post may have been stored though no response said so. Sending the
    /// same message again reuses its operation id, so the server answers with the stored copy.
    var unsettledLivechatSend: UnsettledLivechatSend?
    /// The livechat messages folded into the panes since they were last cleared. A first history
    /// page that replaces the panes brings back the ones it doesn't hold.
    var livechatLog: [LivechatMessage] = []
    /// Counts the conversations this provider has cleared away. A history page requested for an
    /// earlier one is dropped when it arrives.
    private var conversationEpoch = 0

    /// Snapshot channel the view model observes. Latest-wins — the VM only ever
    /// cares about the current conversation, never a backlog.
    package let stream: ChatStream

    package init(
        service: any ChatServicing,
        pageContext: @escaping @Sendable () async -> String?,
        welcomeMessage: String? = nil,
        acceptsImageUploadPrompts: Bool
    ) {
        self.service = service
        self.pageContext = pageContext
        self.welcomeMessage = welcomeMessage
        self.acceptsImageUploadPrompts = acceptsImageUploadPrompts
        (self.stream, self.continuation) = ChatStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Builds the optimistic user-turn echo for a send: the text, then each attachment as posted.
    package static func echo(text: String, attachments: [OutgoingAttachment]) -> [UserContent] {
        var contents: [UserContent] = []
        if !text.isEmpty {
            contents.append(.text(AttributedString(text)))
        }
        contents.append(contentsOf: attachments.map(UserContent.attachment))
        return contents
    }

    /// The greeting, while no older page is known to sit above the conversation. It stays out of
    /// the panes and joins the published snapshot, so a conversation emptied by a delete, an
    /// expired session or a failed first page opens with it, and history lands beneath it.
    private var welcome: ChatResponse? {
        guard !self.paginator.hasOlderPages else { return nil }
        return self.welcomeMessage.map { .text(AttributedString($0)) }
    }

    /// The bot pane as published. The greeting opens the first turn when the bot leads, and is a
    /// turn of its own ahead of a visitor's first message.
    private var publishedIncoming: [Identified<[ChatResponse]>] {
        guard let welcome = self.welcome else { return self.incoming }
        guard self.botLeads, let first = self.incoming.first else {
            return [Identified(id: self.welcomeTurnID, model: [welcome])] + self.incoming
        }
        return [Identified(id: self.welcomeTurnID, model: [welcome] + first.model)] + self.incoming.dropFirst()
    }

    func publish() {
        self.continuation.yield(
            .init(
                user: self.user,
                incoming: self.publishedIncoming,
                isUserInitiatedConversation: self.welcome == nil && !self.botLeads,
                streamingTurnID: self.streamingTurnID,
                liveTurnIDs: self.liveTurnIDs,
                canLoadOlder: !self.paginator.isExhausted
            )
        )
    }

    /// The snapshot stream lives for the whole session and is never finished mid-flight
    /// releasing the provider is its only terminator.
    deinit {
        self.continuation.finish()
    }
}

extension ChatProvider {

    /// Loads the next older page of history and prepends it. No-op when a load is
    /// already in flight or no pages remain. Drives both the first load and the visitor's
    /// request for earlier messages. A page that arrives after a reset, delete or expiry replaced
    /// the conversation is dropped, whatever its outcome.
    ///
    /// A first page asked for once the conversation moved on, after the first attempt failed,
    /// holds what is on screen too, so it takes the panes' place; see ``replacePanes(with:)``.
    /// It waits for no send, and none starts while it is on its way.
    package func loadOlder() async throws {
        let epoch = self.conversationEpoch
        do {
            let cursor = try self.paginator.next()
            let replacesPanes = cursor == nil && !(self.user.isEmpty && self.incoming.isEmpty)
            guard !replacesPanes || self.claimForReplacingPanes() else { return }
            defer { if replacesPanes { self.finishOperation() } }
            let page = try await self.service.fetchHistory(cursor: cursor)
            guard epoch == self.conversationEpoch else { return }
            if replacesPanes {
                self.replacePanes(with: page)
                return
            }
            self.paginator.commit(nextCursor: page.nextCursor)
            if cursor == nil {
                self.historyHead = page.messages.compactMap { Self.milliseconds(of: $0.createdAt) }.max()
            }
            self.prepend(page.messages)
            self.publish()

        } catch where epoch != self.conversationEpoch {
            // The conversation that asked for the page is gone, and its failure with it.
        } catch Paginator.Failure.busy {
            // In progress, do nothing
        } catch Paginator.Failure.exhausted {
            // No more history available, do nothing
        } catch ChatServiceError.sessionExpired {
            // A reply may still be streaming into the panes, so the clear waits for it to settle.
            self.expireSession()
            throw ChatServiceError.sessionExpired

        } catch {
            self.paginator.release()
            // The composer and header read this snapshot; a failed first page must
            // still yield one or the sheet paints an empty NavigationStack.
            self.publish()
            throw error
        }
    }

    /// Rotates the session and clears the conversation.
    /// Throws on failure so the caller can revert the control and surface the error.
    /// Opportunistically loads history for new session.
    /// If the rotation fails the conversation is left intact.
    package func reset() async throws {
        try self.beginOperation()
        defer { self.finishOperation() }

        try await self.service.resetConversation()
        self.clear()
        do {
            try await self.loadOlder()
        } catch {
            self.publish()
        }
    }

    /// Wipes visitor data and ends the session, clearing the conversation.
    /// Throws on failure so the caller can revert the control and surface the error.
    /// a failed delete leaves the conversation intact.
    package func delete() async throws {
        try self.beginOperation()
        defer { self.finishOperation() }

        try await self.service.deleteData()
        self.endConversation()
    }

}

extension ChatProvider {

    /// Claims the provider for a send, reset or delete, which must not interleave.
    func beginOperation() throws(SendFailure) {
        guard !self.isBusy else { throw .busy(self.streamingTurnID != nil ? .streaming : .operation) }
        self.isBusy = true
    }

    /// Ends a send, reset or delete, then folds in the livechat messages held back meanwhile.
    func finishOperation() {
        self.isBusy = false
        if self.expiresAfterOperation {
            self.expiresAfterOperation = false
            self.endConversation()
            return
        }
        let deferred = self.deferredLivechat
        self.deferredLivechat = []
        for item in deferred {
            switch item {
            case .messages(let messages): self.ingestLivechat(messages)
            case .note(let note): self.note(note)
            }
        }
    }

    /// Claims the provider for a first page that will replace the panes, so no send changes them
    /// while it is on its way. With a send already on its way the page waits, and the paginator is
    /// free to ask for it again.
    private func claimForReplacingPanes() -> Bool {
        do {
            try self.beginOperation()
            return true
        } catch {
            self.paginator.release()
            return false
        }
    }

    /// Shows the newest page of history in place of the panes. Everything on screen arrived after
    /// the chat opened, from a send or the livechat log, and the server holds it in the order it
    /// happened, so the page shows it once and in order. Livechat messages newer than the page come
    /// back after it, and so do those that arrived while it was on its way. Session notes go with
    /// the panes.
    private func replacePanes(with page: MessagePage) {
        let log = self.livechatLog
        let deferred = self.deferredLivechat
        let unsettled = self.unsettledLivechatSend
        self.clear()
        self.deferredLivechat = deferred
        self.unsettledLivechatSend = unsettled
        self.paginator.commit(nextCursor: page.nextCursor)
        self.historyHead = page.messages.compactMap { Self.milliseconds(of: $0.createdAt) }.max()
        self.prepend(page.messages)
        self.ingestLivechat(log)
        self.publish()
    }

    /// Empties a conversation that ended with nothing to load in its place: a delete or an
    /// expired session.
    func endConversation() {
        self.clear()
        self.paginator.finish()
        self.publish()
    }

    /// Drops all conversation state and resets pagination, so a reset's reload starts clean.
    func clear() {
        self.conversationEpoch += 1
        self.user = []
        self.incoming = []
        self.livechatLog = []
        self.paginator = Paginator()
        self.streamingTurnID = nil
        self.liveTurnIDs = []
        self.livechatMessageIDs = []
        self.historyHead = nil
        self.botLeads = false
        self.deferredLivechat = []
        self.unsettledLivechatSend = nil
    }

}
