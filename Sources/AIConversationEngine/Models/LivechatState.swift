//
//  LivechatState.swift
//  AIConversationEngine
//

import Foundation

/// Visitor livechat state from `GET /api/v1/chat/livechat/state`.
/// [API ref](https://docs.dialoge.ai/api#model/livechat-state-response)
package struct LivechatState: Decodable, Sendable, Equatable {

    package let status: Status
    package let activeAgent: LivechatAgent?
    package let isAgentTyping: Bool
    package let agentJoinedAt: String?
    package let closedBy: ClosedBy?
    package let feedback: Feedback
    /// Monotonic session version — clients drop out-of-order poll responses.
    package let stateVersion: Int?

    package init(
        status: Status,
        activeAgent: LivechatAgent? = nil,
        isAgentTyping: Bool = false,
        agentJoinedAt: String? = nil,
        closedBy: ClosedBy? = nil,
        feedback: Feedback = Feedback(status: .notAvailable),
        stateVersion: Int? = nil
    ) {
        self.status = status
        self.activeAgent = activeAgent
        self.isAgentTyping = isAgentTyping
        self.agentJoinedAt = agentJoinedAt
        self.closedBy = closedBy
        self.feedback = feedback
        self.stateVersion = stateVersion
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(Status.self, forKey: .status)
        self.activeAgent = try container.decodeIfPresent(LivechatAgent.self, forKey: .activeAgent)
        self.isAgentTyping = try container.decodeIfPresent(Bool.self, forKey: .isAgentTyping) ?? false
        self.agentJoinedAt = try container.decodeIfPresent(String.self, forKey: .agentJoinedAt)
        self.closedBy = try container.decodeIfPresent(ClosedBy.self, forKey: .closedBy)
        self.feedback =
            try container.decodeIfPresent(Feedback.self, forKey: .feedback)
            ?? Feedback(status: .notAvailable)
        self.stateVersion = try? container.decodeIfPresent(Int.self, forKey: .stateVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case status, activeAgent, isAgentTyping, agentJoinedAt, closedBy, feedback, stateVersion
    }

    package enum Status: String, ExtendableEnum, Sendable {
        case inactive, waiting, active, closed, unknown
    }

    package enum ClosedBy: String, ExtendableEnum, Sendable {
        case customer, agent, unknown
    }

    package struct Feedback: Decodable, Sendable, Equatable {
        package let status: Status

        package init(status: Status) {
            self.status = status
        }

        package init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .notAvailable
        }

        private enum CodingKeys: String, CodingKey {
            case status
        }

        package enum Status: String, ExtendableEnum, Sendable {
            case notAvailable = "not_available"
            case pending
            case submitted
            case unknown
        }
    }

    /// A session that still needs polling (queued or talking to an agent).
    package var isInSession: Bool {
        self.status == .waiting || self.status == .active
    }
}
