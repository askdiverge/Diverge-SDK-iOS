//
//  PendingAttachment.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// A photo sitting in the composer, waiting to be sent with the next message.
struct PendingAttachment: Identifiable, Equatable {

    let id: UUID
    let thumbnail: Image
    let attachment: OutgoingAttachment
    let displayName: String

    init(
        id: UUID = UUID(),
        thumbnail: Image,
        attachment: OutgoingAttachment,
        displayName: String
    ) {
        self.id = id
        self.thumbnail = thumbnail
        self.attachment = attachment
        self.displayName = displayName
    }

    static func == (lhs: PendingAttachment, rhs: PendingAttachment) -> Bool {
        lhs.id == rhs.id && lhs.attachment == rhs.attachment && lhs.displayName == rhs.displayName
    }
}
