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

    /// Sends a user message and folds the streamed reply into the conversation.
    /// Fails with `SendFailure` so the VM can surface session-end vs. a retryable error.
    func send(_ text: String) async throws(ChatProvider.SendFailure)

    /// Loads the next older page of history.
    /// no-op while a load is in flight or no pages remain.
    func loadOlder() async throws

    /// Rotates the session and clears the conversation.
    func reset() async throws

    /// Wipes visitor data, ends the session, and clears the conversation.
    func delete() async throws

    /// Folds messages from the livechat poller into the conversation, skipping ids already shown.
    func appendLivechat(_ messages: [LivechatMessage]) async

    /// Sends the visitor's text to the agent while a livechat session is active.
    func sendLivechat(_ text: String) async throws(ChatProvider.SendFailure)

    /// Clears the conversation after the livechat poller saw the session end (401). During a send,
    /// reset or delete the clear waits until the operation finishes.
    func expireSession() async
}
