//
//  RequestHumanAgent.swift
//  AIConversationEngine
//

import Foundation

/// Instructs the client to show a handoff affordance for a human agent.
/// Clients may pass the emitted `part_id` to `POST /livechat/handover`.
///
/// Arrives whole, as a `part` event, in history or in `done`. `part_id` is required; `Part`
/// decodes a marker without it as `.unknown`.
/// [API ref](https://docs.askdiverge.ai/api#model/requesthumanagentmarker)
package struct RequestHumanAgent: Decodable, Sendable, Equatable {

    /// The marker's `part_id`, echoed to `POST /livechat/handover`.
    package let partId: String
}
