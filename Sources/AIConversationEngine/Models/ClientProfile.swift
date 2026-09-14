//
//  ClientProfile.swift
//  AIConversation
//

import Foundation

/// Capability line sent as ``ChatService/clientProfileHeader``.
///
/// Raw values are a backend wire contract: add a case for a new line; never reuse one.
package enum ClientProfile: String, Sendable {

    /// Conversational search, product and suggestion cards — no livechat or forms.
    case productRecommendation = "product-recommendation"
}
