//
//  LivechatRatingController.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Asks the visitor to rate a livechat session that ended while this chat was watching, and sends
/// the rating. The chat view model passes it every livechat snapshot and whether the chat is on
/// screen; the prompt shows while ``model`` is set, and waits for the chat to be on screen.
@MainActor
@Observable
final class LivechatRatingController {

    typealias Submitter = @Sendable (LivechatFeedbackRequest) async throws -> Void

    /// The rating draft while the prompt is up.
    private(set) var model: RatingSubmissionModel?

    @ObservationIgnored private let submitFeedback: Submitter
    /// Runs when the submit finds the visitor session ended (401); see ``bind(onSessionExpired:refresh:)``.
    @ObservationIgnored private var onSessionExpired: (@MainActor () async -> Void)?
    /// Reads the livechat state again, so a rating the server already holds closes the prompt.
    @ObservationIgnored private var refresh: (@MainActor () async -> Void)?
    /// This screen saw the current session close, so its feedback may be asked for.
    @ObservationIgnored private var sawClose = false
    /// The visitor rated or skipped this close.
    @ObservationIgnored private var isDone = false
    /// The last snapshot said the closed session's feedback is pending.
    @ObservationIgnored private var feedbackPending = false
    /// The chat is visible and the app active.
    @ObservationIgnored private var isOnScreen = true
    /// Bumped when a new session replaces the closed one, so a rating sent for the old one can't
    /// end or close anything after it.
    @ObservationIgnored private var epoch = 0

    init(submitFeedback: @escaping Submitter) {
        self.submitFeedback = submitFeedback
    }

    /// Sets what runs on a 401 and how the livechat state is read again. The first handlers stay.
    func bind(
        onSessionExpired: @escaping @MainActor () async -> Void,
        refresh: @escaping @MainActor () async -> Void
    ) {
        guard self.onSessionExpired == nil else { return }
        self.onSessionExpired = onSessionExpired
        self.refresh = refresh
    }

    /// Follows a livechat snapshot. The prompt opens when a close seen live has feedback pending,
    /// and goes away when a snapshot shows the feedback no longer pending or a new session starts.
    /// After a close the poller stops, so a rating given elsewhere shows when a send is refused.
    func update(previous: LivechatState.Status, state: LivechatState, isRestored: Bool) {
        guard state.status == .closed else {
            self.sawClose = false
            self.isDone = false
            self.feedbackPending = false
            self.epoch += 1
            self.dropModel()
            return
        }
        if previous.isInSession, !isRestored {
            self.sawClose = true
        }
        self.feedbackPending = state.feedback.status == .pending
        if self.feedbackPending {
            self.offerIfReady()
        } else if self.model?.isSubmitting == false {
            self.dropModel()
        }
    }

    /// Follows the chat going on or off screen. A close seen while it was off screen is asked
    /// about once it is back.
    func setOnScreen(_ onScreen: Bool) {
        self.isOnScreen = onScreen
        self.offerIfReady()
    }

    /// Sends the rating. A 409 means the session holds a rating already, so the prompt closes. Any
    /// other refused rating stays on the prompt for another try, and the state is read again in
    /// case the server already holds one. The result of a rating sent for a session a new one has
    /// since replaced is dropped.
    func submit(score: Int, feedback: String?) async {
        guard let model = self.model, model.beginSubmitting(score: score, feedback: feedback) else { return }
        let epoch = self.epoch
        do {
            try await self.submitFeedback(LivechatFeedbackRequest(rating: score, feedback: feedback))
            guard epoch == self.epoch else { return }
            self.isDone = true
            self.dropModel()
        } catch {
            guard epoch == self.epoch else { return }
            switch error {
            case ChatServiceError.sessionExpired:
                self.dropModel()
                await self.onSessionExpired?()
            case ChatServiceError.conflict:
                self.isDone = true
                self.dropModel()
            default:
                model.markFailed(message: L10n.noticeSendFailed.string)
                await self.refresh?()
            }
        }
    }

    /// The visitor skipped the prompt; nothing is sent and this close isn't asked about again.
    func dismiss() {
        self.isDone = true
        self.dropModel()
    }

    private func offerIfReady() {
        guard self.isOnScreen, self.feedbackPending, self.sawClose, !self.isDone, self.model == nil else { return }
        self.model = RatingSubmissionModel()
    }

    private func dropModel() {
        if self.model != nil {
            self.model = nil
        }
    }
}
