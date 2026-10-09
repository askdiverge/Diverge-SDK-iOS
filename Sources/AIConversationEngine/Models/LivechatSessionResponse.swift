//
//  LivechatSessionResponse.swift
//  AIConversationEngine
//

import Foundation

/// The `POST /livechat/handover` response. Only `status` is read: `waiting` for a new session,
/// or `active` when the API hands back one that is already open.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatsessionresponse)
struct LivechatSessionResponse: Decodable, Sendable {
    let status: LivechatState.Status
}
