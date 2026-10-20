//
//  ChatProviding.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

/// The view-model–facing surface of `ChatProvider`. The VM observes `stream` for ready-
/// to-render conversation snapshots and drives the session with the command methods
package protocol ChatProviding: Sendable {

    /// Latest-wins stream of conversation snapshots to mirror onto the main actor.
    nonisolated var stream: AsyncStream<ConversationSnapshot> { get }

    /// Sends a user message (text and/or attachments) and folds the streamed reply into the
    /// conversation. Fails with `SendFailure` so the VM can surface session-end vs. a retryable error.
    func send(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure)

    /// Loads the next older page of history.
    /// no-op while a load is in flight or no pages remain.
    func loadOlder() async throws

    /// Rotates the session and clears the conversation.
    func reset() async throws

    /// Wipes visitor data, ends the session, and clears the conversation.
    func delete() async throws

    /// Folds messages from the livechat poller into the conversation, skipping ids already shown.
    func appendLivechat(_ messages: [LivechatMessage]) async

    /// Appends an SDK-minted livechat boundary note (queued / agent joined / ended).
    func note(_ note: LivechatNote) async

    /// Sends the visitor's text and/or attachments to the agent while a livechat session is active.
    func sendLivechat(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure)

    /// Clears the conversation after a call outside the provider — the livechat poller, a form
    /// submit — saw the session end (401). During a send, reset or delete the clear waits until
    /// the operation finishes.
    func expireSession() async
}

extension ChatProviding {
    /// Text-only convenience for call sites that never attach media.
    package func send(_ text: String) async throws(ChatProvider.SendFailure) {
        try await self.send(text, attachments: [])
    }

    /// Text-only livechat send.
    package func sendLivechat(_ text: String) async throws(ChatProvider.SendFailure) {
        try await self.sendLivechat(text, attachments: [])
    }
}
