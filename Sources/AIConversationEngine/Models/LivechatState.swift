//
//  LivechatState.swift
//  AIConversationEngine
//

import Foundation

/// The visitor's livechat state from `GET /api/v1/chat/livechat/state`.
/// [API ref](https://docs.askdiverge.ai/api#model/livechatstateresponse)
package struct LivechatState: Decodable, Sendable, Equatable {

    package let status: Status
    /// The agent shown to the visitor; `nil` until one joins.
    package let activeAgent: LivechatAgent?
    package let isAgentTyping: Bool
    /// ISO 8601 date-time the agent joined; `nil` while waiting.
    package let agentJoinedAt: String?
    package let closedBy: ClosedBy?
    package let feedback: Feedback
    /// Monotonic session version. A poll response older than one already applied is dropped.
    package let stateVersion: Int?

    /// Whether the session still needs polling: queued, or talking to an agent.
    package var isInSession: Bool {
        self.status.isInSession
    }

    /// Where the visitor's latest livechat session stands, decided by the backend: `inactive`
    /// before any handover, `waiting` in the queue, `active` with an agent, and `closed` once
    /// either side ends it. The client polls while `waiting` or `active`. A case is added when the
    /// backend introduces a new session stage.
    /// [API ref](https://docs.askdiverge.ai/api#model/livechatstateresponse)
    package enum Status: String, ExtendableEnum, Sendable {
        case inactive, waiting, active, closed, unknown

        /// Queued, or talking to an agent.
        package var isInSession: Bool {
            self == .waiting || self == .active
        }
    }

    /// Who ended the latest session, set by the backend when it closes: the visitor
    /// (`customer`) or the `agent`. The client picks its closing copy from it. A case is added
    /// when another party can close a session.
    /// [API ref](https://docs.askdiverge.ai/api#model/livechatstateresponse)
    package enum ClosedBy: String, ExtendableEnum, Sendable {
        case customer, agent, unknown
    }

    /// Whether the visitor can rate the latest session.
    /// [API ref](https://docs.askdiverge.ai/api#model/livechatfeedbackstate)
    package struct Feedback: Decodable, Sendable, Equatable {
        package let status: Status

        /// Whether the visitor can rate the latest session, decided by the backend: `pending` once
        /// a closed session can be rated, `submitted` after the visitor rated it, `not_available`
        /// otherwise. The client offers a rating only while `pending`. A case is added when the
        /// backend adds a feedback stage.
        /// [API ref](https://docs.askdiverge.ai/api#model/livechatfeedbackstate)
        package enum Status: String, ExtendableEnum, Sendable {
            case notAvailable = "not_available"
            case pending
            case submitted
            case unknown
        }
    }
}

extension LivechatState {

    /// A state the client publishes before the server has reported one: no agent, not typing.
    init(status: Status, feedback: Feedback.Status = .notAvailable) {
        self.init(
            status: status,
            activeAgent: nil,
            isAgentTyping: false,
            agentJoinedAt: nil,
            closedBy: nil,
            feedback: Feedback(status: feedback),
            stateVersion: nil
        )
    }
}
