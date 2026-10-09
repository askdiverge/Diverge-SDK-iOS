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
struct LivechatCloseRequest: Encodable, Sendable, Equatable {
    let reason: String?
}
