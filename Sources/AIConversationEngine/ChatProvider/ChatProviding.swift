//
//  ChatProviding.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// The view-model–facing surface of `ChatProvider`. The VM observes `stream` for ready-
/// to-render conversation snapshots and drives the session with the command methods
package protocol ChatProviding: Sendable {

    /// Latest-wins stream of conversation snapshots to mirror onto the main actor.
    nonisolated var stream: AsyncStream<ConversationSnapshot> { get }

    /// Sends a user message (text and/or attachments) and folds the streamed reply into the
    /// conversation. Fails with `SendFailure` so the VM can surface session-end vs. a retryable
    /// error.
    func send(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure)

    /// Loads the next older page of history and prepends it. Returns whether turns were
    /// prepended — `false` for the no-ops (a load already in flight, history exhausted, an
    /// empty page) so the UI can tell "nothing to re-pin to" from "a page is about to land".
    @discardableResult
    func loadOlder() async throws -> Bool

    /// Rotates the session and clears the conversation.
    func reset() async throws

    /// Wipes visitor data, ends the session, and clears the conversation.
    func delete() async throws

    /// GDPR portability — raw JSON from `GET /api/v1/chat/export`. Does not clear the
    /// conversation or drop the token. A 401 surfaces as ``ChatServiceError/sessionExpired``.
    func exportMyData() async throws(ChatServiceError) -> Data

    /// Appends livechat transcript messages (poll or send response), deduped by `message_id`.
    func appendLivechat(_ messages: [LivechatMessage]) async

    /// Appends a locally minted livechat boundary note.
    func note(_ note: LivechatNote) async

    /// Sends a visitor message on the livechat channel while the session is `active`.
    func sendLivechat(_ text: String, attachments: [OutgoingAttachment]) async throws(ChatProvider.SendFailure)

    /// Drops local conversation state after a 401 detected outside send (livechat poller).
    func expireSession() async
}

extension ChatProviding {

    /// Text-only convenience — suggestion taps and the pre-attachment composer path.
    package func send(_ text: String) async throws(ChatProvider.SendFailure) {
        try await self.send(text, attachments: [])
    }

    /// Text-only livechat send.
    package func sendLivechat(_ text: String) async throws(ChatProvider.SendFailure) {
        try await self.sendLivechat(text, attachments: [])
    }
}
