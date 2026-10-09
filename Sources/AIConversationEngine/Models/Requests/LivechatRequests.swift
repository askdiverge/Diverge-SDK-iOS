//
//  LivechatRequests.swift
//  AIConversationEngine
//

import Foundation

/// Body for `POST /api/v1/chat/livechat/handover`.
/// [API ref](https://docs.askdiverge.ai/api#model/livechathandoverrequest)
package struct LivechatHandoverRequest: Encodable, Sendable, Equatable {

    /// The `platform` this SDK reports: a native app. The backend records it on the session and
    /// shows it to agents beside `mobile_web` and `website` sessions.
    package static let nativePlatform = "mobile_app"

    let platform = Self.nativePlatform
    let source: Source
    /// The `request_human_agent` marker that prompted the handover, if one did.
    let partId: String?
    let clientContext: LivechatClientContext?

    /// What triggered the handover. The API takes any string; these are the two the SDK sends.
    package enum Source: String, Encodable, Sendable {
        /// The visitor tapped the handover control.
        case manualButton = "manual_button"
        /// The visitor accepted a `request_human_agent` marker in an assistant reply.
        case assistantMarker = "assistant_marker"
    }
}

/// Body for `POST /api/v1/chat/livechat/typing`.
/// [API ref](https://docs.askdiverge.ai/api#model/livechattypingrequest)
struct LivechatTypingRequest: Encodable, Sendable, Equatable {
    let isTyping: Bool
}

/// Body for `POST /api/v1/chat/livechat/close`.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatcloserequest)
package struct LivechatCloseRequest: Encodable, Sendable, Equatable {

    /// The `reason` sent when the visitor ends the session from the header control. The backend
    /// records it as the session's close reason.
    package static let endedByVisitorReason = "Switched back to AI chatbot mode"
    /// The `reason` sent when the visitor resets the chat while a session is open.
    package static let resetReason = "Chat reset"

    let reason: String?
}
