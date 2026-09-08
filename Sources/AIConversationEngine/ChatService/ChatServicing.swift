//
//  ChatServicing.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-04.
//

import Foundation

/// Facade interface over the Dialoge chat API.
///
/// Every method fails with `ChatServiceError` — lower-layer errors are
/// translated at this boundary.
package protocol ChatServicing: Sendable {

    /// paginated history, newest first.
    /// Pass the previous page's `nextCursor` to fetch the next page; `nil` for the first.
    func fetchHistory(cursor: String?) async throws(ChatServiceError) -> MessagePage

    /// Sends a message (text and/or attachments) and streams the response as SSE events until
    /// `done`/`error` terminates it. `page` is per-message context. Every failure (transport,
    /// 401, or a stream `error` event) is delivered on the stream's throwing channel as
    /// `ChatServiceError`.
    func sendMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error>

    /// Submits a marker-triggered action (contact form, support ticket, custom form).
    /// Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``.
    func submitAction(_ request: SubmitActionRequest) async throws(ChatServiceError) -> SubmitActionResponse

    /// Rates the active conversation 1–5 with optional free-text feedback.
    /// Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``. The server
    /// returns an empty 200; subsequent calls overwrite the previous rating.
    func rateConversation(_ request: RateConversationRequest) async throws(ChatServiceError)

    /// Rotates the session — invalidates the current token and obtains a fresh
    /// one via the host's reset hook. The caller clears local conversation state.
    func resetConversation() async throws(ChatServiceError)

    /// Full visitor-data wipe via the host's delete hook. The session ends, no
    /// replacement token is fetched. The caller clears local conversation state
    func deleteData() async throws(ChatServiceError)

    /// GDPR portability — raw JSON body of `GET /api/v1/chat/export`. Session-bound; a 401
    /// surfaces as ``ChatServiceError/sessionExpired``. Does **not** drop the token.
    func exportMyData() async throws(ChatServiceError) -> Data

    // MARK: Livechat

    /// Current livechat session state. Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``.
    func fetchLivechatState() async throws(ChatServiceError) -> LivechatState

    /// Request handover to a human agent. `source` is `"manual_button"` or `"assistant_marker"`;
    /// `partId` is set when the handover was triggered from a marker. `clientContext` is optional
    /// environment metadata for agents. A 409 means livechat is offline.
    func requestLivechatHandover(
        source: String,
        partId: String?,
        clientContext: LivechatClientContext?
    ) async throws(ChatServiceError)

    /// Incremental livechat transcript page. Pass the highest `sequenceNumber` already seen as `after`.
    func fetchLivechatMessages(after sequenceNumber: Int64?) async throws(ChatServiceError) -> LivechatMessagePage

    /// Sends a visitor livechat message while the session is `active`. Returns the stored message.
    func sendLivechatMessage(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) async throws(ChatServiceError) -> LivechatMessage

    /// Updates the visitor typing indicator. Active sessions only; failures are soft at the call site.
    func sendLivechatTyping(isTyping: Bool) async throws(ChatServiceError)

    /// Closes the current livechat session from the visitor side.
    func closeLivechat(reason: String?) async throws(ChatServiceError)

    /// Post-session CSAT for the latest **closed** livechat session.
    /// Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``.
    /// A 409 means the session is still open or feedback was already submitted.
    func submitLivechatFeedback(
        _ request: RateConversationRequest
    ) async throws(ChatServiceError) -> LivechatFeedbackResponse

    /// Full form definition. Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``.
    func fetchForm(id: String) async throws(ChatServiceError) -> ChatFormDefinition

    /// Current visitor session values (for prefill). Session-bound.
    func fetchSession() async throws(ChatServiceError) -> ChatSessionState

    /// Partial update of session values through a form. Session-bound.
    /// A 409 means the form cannot be submitted in the current livechat state
    /// (e.g. `livechat_waiting` while not queued).
    func patchFormValues(
        formId: String,
        values: [String: String]
    ) async throws(ChatServiceError) -> ChatSessionState
}

extension ChatServicing {

    /// Text-only convenience for call sites that never attach media.
    package func sendMessage(
        _ text: String,
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        self.sendMessage(text, attachments: [], page: page)
    }
}
