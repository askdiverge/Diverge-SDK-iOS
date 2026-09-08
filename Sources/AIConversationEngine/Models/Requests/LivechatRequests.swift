//
//  LivechatRequests.swift
//  AIConversationEngine
//

import Foundation

/// Body for `POST /api/v1/chat/livechat/handover`.
package struct LivechatHandoverRequest: Encodable, Sendable, Equatable {
    package let platform: String
    package let source: String?
    package let partId: String?
    /// Optional environment snapshot for agents while the visitor waits.
    package let clientContext: LivechatClientContext?

    package init(
        platform: String,
        source: String?,
        partId: String?,
        clientContext: LivechatClientContext? = nil
    ) {
        self.platform = platform
        self.source = source
        self.partId = partId
        self.clientContext = clientContext
    }

    package static let mobileAppPlatform = "mobile_app"
    package static let manualButtonSource = "manual_button"
    package static let assistantMarkerSource = "assistant_marker"
}

/// Body for `POST /api/v1/chat/livechat/typing`.
struct LivechatTypingRequest: Encodable, Sendable, Equatable {
    let isTyping: Bool
}

/// Body for `POST /api/v1/chat/livechat/close`.
struct LivechatCloseRequest: Encodable, Sendable, Equatable {
    let reason: String?
}
