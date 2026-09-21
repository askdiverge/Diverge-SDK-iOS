//
//  ClientProfile.swift
//  AIConversation
//

import Foundation

/// The set of chat features this SDK build can render, declared to the backend on every
/// authenticated call as ``ChatService/clientProfileHeader``.
///
/// It describes the *product line* of the SDK binary — not the visitor, not where in the host
/// app the chat is opened. The backend uses it to decide which tools the assistant may reach for:
/// a build that has no UI for livechat handover or forms must never be offered them, however
/// the visitor phrases the request. Gating on this declared capability is deliberate — gating on
/// ``ChatService/sdkVersionHeader`` alone would force the backend to maintain version ranges
/// that have to be widened on every release.
///
/// One SDK release ships exactly one profile. A new case is added only when a new product line
/// ships (e.g. a customer-service line that renders livechat and forms). Raw values are a wire
/// contract shared with the backend: never rename or repurpose an existing one.
package enum ClientProfile: String, Sendable {

    /// Conversational search with product and suggestion cards. Renders no livechat handover,
    /// contact forms or support tickets, so the backend must not offer them.
    case productRecommendation = "product-recommendation"
}
