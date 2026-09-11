//
//  UserContent.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// One bubble in a user turn — the user-pane mirror of ``ChatResponse``.
///
/// Text is the common case; `image` / `file` cover visitor uploads (this session's optimistic
/// echo, or history that includes a photo the visitor sent from the web widget).
package enum UserContent: Sendable, Equatable {
    case text(AttributedString)
    case image(MessageImage)
    case file(MessageFile)
}
