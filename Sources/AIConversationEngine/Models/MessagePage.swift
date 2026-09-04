//
//  MessagePage.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// Paginated conversation history returned by `GET /api/v1/chat/messages`.
/// Messages are in reverse chronological order.
///
/// `nextCursor` — you can only paginate when a cursor is present, so cursor
/// presence is the actionable "more pages" signal.
/// [API ref](https://docs.dialoge.ai/api#model/message-page)
package struct MessagePage: Decodable, Sendable, Equatable {

    package let messages: [Message]
    /// Opaque cursor for the next page. `nil` when no more pages remain.
    package let nextCursor: String?
}
