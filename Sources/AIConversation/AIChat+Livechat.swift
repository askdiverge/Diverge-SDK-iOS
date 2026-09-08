//
//  AIChat+Livechat.swift
//  AIConversation
//

import Foundation

public extension AIChat {

    /// Last-known livechat session surface for host badges / re-present decisions.
    ///
    /// Delivered via ``Configuration/onLivechatSessionChange``. The poller still parks when
    /// `ChatView` is off-screen or the app backgrounds — this is **not** a live dismissed feed.
    /// While dismissed, the last value the host received stays frozen until re-present catch-up.
    struct LivechatSessionInfo: Sendable, Equatable {
        /// Coarse session phase — does not expose package ``LivechatState/Status``.
        public enum Status: String, Sendable, Equatable {
            case inactive
            case waiting
            case active
            case closed
        }

        public let status: Status
        /// Non-empty agent name only while ``status`` is ``Status/active``; otherwise `nil`.
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
