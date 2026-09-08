//
//  LivechatMirror.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// View-model owned livechat surface: config + the latest poller snapshot.
///
/// Isolated here so `ChatView+Livechat` can mutate through methods instead of
/// underscore-prefixed fields on the view model.
@MainActor
@Observable
final class LivechatMirror {

    private(set) var settings = LivechatSettings()
    private(set) var status: LivechatState.Status = .inactive
    private(set) var activeAgent: LivechatAgent?
    private(set) var isAgentTyping = false
    private(set) var feedback: LivechatState.Feedback = LivechatState.Feedback(status: .notAvailable)
    /// Set when the poller sees a 401; `ChatView` turns it into the session-ended alert.
    private(set) var sessionEnded = false

    var enabled: Bool { self.settings.enabled }
    var available: Bool { self.settings.isAvailable }
    var showLogo: Bool { self.settings.showLivechatLogo }
    var isInSession: Bool { self.status.isInSession }
    /// Whether `POST /livechat/messages` may carry image/file parts while active.
    var attachmentsEnabled: Bool { self.settings.attachmentsEnabled }
    /// Decoded byte budget for an active-session upload (from `/config`).
    var maxAttachmentSizeBytes: Int { self.settings.maxAttachmentSizeBytes }

    func apply(settings: LivechatSettings) {
        self.settings = settings
    }

    func apply(snapshot: LivechatSnapshot) {
        self.status = snapshot.state.status
        self.activeAgent = snapshot.state.activeAgent
        self.isAgentTyping = snapshot.state.isAgentTyping
        self.feedback = snapshot.state.feedback
    }

    func markStatus(_ status: LivechatState.Status, agent: LivechatAgent? = nil) {
        self.status = status
        if let agent {
            self.activeAgent = agent
        }
        if !status.isInSession {
            self.activeAgent = nil
            self.isAgentTyping = false
        }
        if status != .active {
            self.isAgentTyping = false
        }
        if status == .waiting || status == .active {
            self.feedback = LivechatState.Feedback(status: .notAvailable)
        }
    }

    /// After a successful CSAT submit (or 409 already-submitted).
    func markFeedbackSubmitted() {
        self.feedback = LivechatState.Feedback(status: .submitted)
    }

    func markSessionEnded() {
        self.sessionEnded = true
        self.status = .inactive
        self.activeAgent = nil
        self.isAgentTyping = false
        self.feedback = LivechatState.Feedback(status: .notAvailable)
    }

    func reset() {
        self.status = .inactive
        self.activeAgent = nil
        self.isAgentTyping = false
        self.sessionEnded = false
        self.feedback = LivechatState.Feedback(status: .notAvailable)
    }

    /// Display name for the composer / typing line — localised fallback when the agent is unnamed.
    var agentDisplayName: String {
        let name = self.activeAgent?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? L10n.livechatAgentFallback.string : name
    }
}
