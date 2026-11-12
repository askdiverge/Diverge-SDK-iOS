//
//  RatingSubmissionModel.swift
//  AIConversation
//

import Foundation

/// Draft and submission state for a livechat CSAT (or conversation rating) overlay.
///
/// Two steps: pick a score (1–5), then optionally type feedback when the score is ≤ 3.
/// Scores 4–5 skip the feedback step and submit immediately.
@MainActor
@Observable
final class RatingSubmissionModel {

    enum Phase: Equatable {
        case picking
        case feedback(score: Int)
        case submitting(score: Int, feedback: String?)
        case failed(score: Int, feedback: String?, message: String)
    }

    private(set) var phase: Phase = .picking
    var feedbackText = ""

    var isSubmitting: Bool {
        if case .submitting = self.phase { return true }
        return false
    }

    var score: Int? {
        switch self.phase {
        case .picking: nil
        case .feedback(let score), .submitting(let score, _), .failed(let score, _, _): score
        }
    }

    /// Scores at or below this threshold open the free-text feedback step (web parity).
    static let feedbackThreshold = 3

    /// True once a score of 1–3 has been picked (feedback, submitting, or failed on that score).
    /// Send on this step posts the score, with the comment when there is one.
    var isFeedbackStep: Bool {
        guard let score, score <= Self.feedbackThreshold else { return false }
        if case .picking = self.phase { return false }
        return true
    }

    /// Advances from the scale. Returns `true` when the score needs the free-text feedback
    /// step (1–3); `false` when the caller should submit immediately (4–5).
    @discardableResult
    func pick(_ score: Int) -> Bool {
        guard (1...5).contains(score), !self.isSubmitting else { return false }
        if score <= Self.feedbackThreshold {
            self.phase = .feedback(score: score)
            self.feedbackText = ""
            return true
        }
        return false
    }

    /// Marks the model as in-flight. Returns `false` if already submitting.
    @discardableResult
    func beginSubmitting(score: Int, feedback: String?) -> Bool {
        guard !self.isSubmitting else { return false }
        self.phase = .submitting(score: score, feedback: feedback)
        return true
    }

    func markFailed(message: String) {
        let score: Int
        let feedback: String?
        switch self.phase {
        case .submitting(let scoreValue, let feedbackValue), .failed(let scoreValue, let feedbackValue, _):
            score = scoreValue
            feedback = feedbackValue
        case .feedback(let scoreValue):
            score = scoreValue
            feedback = self.feedbackText
        case .picking:
            return
        }
        self.phase = .failed(score: score, feedback: feedback, message: message)
    }

    /// After a failure, editing the feedback text returns to the feedback step.
    func editingAfterFailure() {
        if case .failed(let score, let feedback, _) = self.phase {
            self.feedbackText = feedback ?? ""
            self.phase = .feedback(score: score)
        }
    }
}
