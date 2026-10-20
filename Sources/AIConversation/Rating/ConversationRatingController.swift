//
//  ConversationRatingController.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Holds the conversation close-rating draft (`POST /rate`) while the prompt is up.
@MainActor
@Observable
final class ConversationRatingController {

    typealias Submitter = @Sendable (RateConversationRequest) async throws -> Void

    /// The rating draft while the prompt is up.
    private(set) var model: RatingSubmissionModel?

    @ObservationIgnored private let submitRating: Submitter
    @ObservationIgnored private let ratingSession: RatingSession
    @ObservationIgnored private var onSessionExpired: (@MainActor () async -> Void)?

    init(ratingSession: RatingSession, submitRating: @escaping Submitter) {
        self.ratingSession = ratingSession
        self.submitRating = submitRating
    }

    /// Sets what runs on a 401. The first handler stays.
    func bind(onSessionExpired: @escaping @MainActor () async -> Void) {
        guard self.onSessionExpired == nil else { return }
        self.onSessionExpired = onSessionExpired
    }

    /// Opens a fresh draft for the close overlay.
    @discardableResult
    func begin() -> RatingSubmissionModel {
        let model = RatingSubmissionModel()
        self.model = model
        return model
    }

    /// Scale Skip / backdrop — dismiss without POSTing.
    func dismiss() {
        self.model = nil
    }

    /// Sends the rating. Marks ``RatingSession`` on success so a later close does not re-ask.
    /// Non-401 failures keep the draft for retry.
    func submit(score: Int, feedback: String?) async -> Bool {
        guard let model = self.model, model.beginSubmitting(score: score, feedback: feedback) else {
            return false
        }
        do {
            try await self.submitRating(RateConversationRequest(rating: score, feedback: feedback))
            self.ratingSession.markRated()
            self.model = nil
            return true
        } catch ChatServiceError.sessionExpired {
            self.model = nil
            await self.onSessionExpired?()
            return false
        } catch {
            model.markFailed(message: L10n.noticeSendFailed.string)
            return false
        }
    }

    /// Whether this ``AIChat`` instance has already submitted a conversation rating.
    var hasRated: Bool {
        self.ratingSession.hasRated
    }

    func clearSession() {
        self.ratingSession.clear()
        self.model = nil
    }
}
