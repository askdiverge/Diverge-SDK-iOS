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

    /// sends a text message and streams the
    /// response as SSE events until `done`/`error` terminates it.
    /// `page` is per-message context .
    /// every failure (transport, 401, or a stream `error` event) is delivered on the stream's throwing channel as
    /// `ChatServiceError`.
    func sendMessage(
        _ text: String,
        page: String?
    ) -> AsyncThrowingStream<StreamEvent, any Error>

    /// Submits a marker-triggered action (contact form, support ticket, custom form).
    /// Session-bound — a 401 surfaces as ``ChatServiceError/sessionExpired``.
    func submitAction(_ request: SubmitActionRequest) async throws(ChatServiceError) -> SubmitActionResponse

    /// Full form definition for a thin `show_form` marker. Session agnostic like `/config` —
    /// a 401 is retried once with a fresh token.
    func fetchForm(id: String) async throws(ChatServiceError) -> ChatFormDefinition

    /// Rotates the session — invalidates the current token and obtains a fresh
    /// one via the host's reset hook. The caller clears local conversation state.
    func resetConversation() async throws(ChatServiceError)

    /// Full visitor-data wipe via the host's delete hook. The session ends, no
    /// replacement token is fetched. The caller clears local conversation state
    func deleteData() async throws(ChatServiceError)
}
