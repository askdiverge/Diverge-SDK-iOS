//
//  UserContent.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import Foundation

/// One bubble in a user turn — the user-pane mirror of ``ChatResponse``.
package enum UserContent: Sendable, Equatable {
    /// Text the visitor typed.
    case text(AttributedString)
    /// An upload sent from this device, kept as the payload that was posted.
    case attachment(OutgoingAttachment)
}
