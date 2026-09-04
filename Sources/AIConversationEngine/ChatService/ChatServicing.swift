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

    /// Rotates the session — invalidates the current token and obtains a fresh
    /// one via the host's reset hook. The caller clears local conversation state.
    func resetConversation() async throws(ChatServiceError)

    /// Full visitor-data wipe via the host's delete hook. The session ends, no
    /// replacement token is fetched. The caller clears local conversation state
    func deleteData() async throws(ChatServiceError)
}
