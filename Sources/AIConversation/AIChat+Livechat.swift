//
//  AIChat+Livechat.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

public extension AIChat {

    /// The visitor's livechat session as the chat last saw it: whether they are queued or
    /// talking to an agent, and the agent's name.
    ///
    /// Delivered through ``Configuration`` `onLivechatSessionChange` while the chat is on screen.
    /// After the chat is dismissed, the last value delivered describes the session as it was
    /// then; the next presentation delivers the current one.
    struct LivechatSessionInfo: Sendable, Equatable {

        /// The phase of the visitor's livechat session. New phases may be added in minor
        /// releases, so a `switch` over it needs a `default` case.
        public struct Status: Hashable, Sendable {
            private let name: String

            private init(_ name: String) {
                self.name = name
            }

            /// No livechat session is open.
            public static let inactive = Status("inactive")
            /// The visitor is queued for an agent.
            public static let waiting = Status("waiting")
            /// An agent is talking to the visitor.
            public static let active = Status("active")
            /// The session has ended.
            public static let closed = Status("closed")
        }

        public let status: Status
        /// The connected agent's name while ``status`` is ``Status/active`` and the agent has one.
        public let agentDisplayName: String?

        public init(status: Status, agentDisplayName: String? = nil) {
            self.status = status
            if status == .active {
                let trimmed = agentDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.agentDisplayName = (trimmed?.isEmpty == false) ? trimmed : nil
            } else {
                self.agentDisplayName = nil
            }
        }
    }
}

extension AIChat.LivechatSessionInfo {

    /// The host's view of a session the poller reports as `status`, with `agentName` while active.
    init(_ status: LivechatState.Status, agentName: String?) {
        let phase: Status = switch status {
        case .waiting: .waiting
        case .active: .active
        case .closed: .closed
        case .inactive, .unknown: .inactive
        }
        self.init(status: phase, agentDisplayName: agentName)
    }
}
