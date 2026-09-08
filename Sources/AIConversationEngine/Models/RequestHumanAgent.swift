//
//  RequestHumanAgent.swift
//  AIConversationEngine
//

import Foundation

/// Instructs the client to show a handoff affordance for a human agent.
/// Clients may pass the emitted `part_id` to `POST /livechat/handover`.
///
/// Arrives only as a full `part` / history / `done` — markers never stream via `part_delta`.
/// [API ref](https://docs.dialoge.ai/api#model/request-human-agent-marker)
package struct RequestHumanAgent: Decodable, Sendable, Equatable {

    package let partId: String

    package init(partId: String) {
        self.partId = partId
    }

    /// Lenient decode — without `part_id` the part falls back to `.unknown` upstream.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.partId = try container.decode(String.self, forKey: .partId)
    }

    private enum CodingKeys: String, CodingKey {
        case partId
    }
}
