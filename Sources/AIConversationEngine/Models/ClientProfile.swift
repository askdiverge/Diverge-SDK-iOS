//
//  ClientProfile.swift
//  AIConversation
//

import Foundation

/// The capability line an SDK release ships, sent as ``ChatService/clientProfileHeader``.
///
/// The backend selects a tool set and system prompt from this rather than from the SemVer in
/// ``ChatService/sdkVersionHeader``, so gating never depends on parsing a version range that
/// has to be widened on every release. A host on ``productRecommendation`` is never offered
/// livechat handover, contact or support-ticket forms: those tools are not registered for the
/// profile, so the model cannot reach for them regardless of how the visitor phrases the ask.
///
/// The raw values are a wire contract shared with the backend — changing one is a breaking
/// change. Add a case when a new line ships; never repurpose an existing one.
package enum ClientProfile: String, Sendable {

    /// Product recommendation only — conversational search, product and suggestion cards.
    case productRecommendation = "product-recommendation"
}
