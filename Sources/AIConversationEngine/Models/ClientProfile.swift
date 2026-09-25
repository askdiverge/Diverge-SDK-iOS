//
//  ClientProfile.swift
//  AIConversation
//

import Foundation

/// The set of chat features this SDK build renders, declared to the backend on every
/// authenticated call as ``ChatService/clientProfileHeader``.
///
/// It describes the product line of the binary. The backend registers the assistant's tools
/// from it, so the assistant can only reach for features this build has UI for, however the
/// visitor phrases the request. Declaring the capability directly keeps the backend rule a
/// single equality check; a rule derived from ``ChatService/sdkVersionHeader`` would need a
/// version range per platform, widened on every release.
///
/// One SDK release ships exactly one profile. A new case is added when a new product line
/// ships (for example a customer-service line that renders livechat and forms). Raw values are a
/// wire contract shared with the backend and the other SDKs; each value stays bound to the line
/// it was introduced for.
package enum ClientProfile: String, Sendable {

    /// Conversational search with product and suggestion cards. The backend limits the
    /// assistant's tools to that set.
    case productRecommendation = "product-recommendation"
}
