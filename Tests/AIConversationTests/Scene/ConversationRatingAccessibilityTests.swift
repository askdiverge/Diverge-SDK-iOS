//
//  ConversationRatingAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

@Suite("ConversationRatingView — accessibility contract")
struct ConversationRatingAccessibilityTests {

    @Test("score labels are wired to non-empty string resources")
    func scoreLabels() {
        for score in 1...5 {
            #expect(!RatingScaleView.label(for: score).isEmpty)
        }
        #expect(RatingScaleView.label(for: 1) == L10n.ratingScore1.string)
        #expect(RatingScaleView.label(for: 5) == L10n.ratingScore5.string)
    }

    @Test("rating copy exists in every locale")
    func catalogCoverage() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "rating.title", "rating.message", "rating.skip",
            "rating.skipHint", "rating.skipFeedbackHint",
            "rating.feedbackTitle", "rating.feedbackPlaceholder", "rating.feedbackSubmit",
            "rating.failed", "rating.close",
            "rating.score.1", "rating.score.2", "rating.score.3", "rating.score.4", "rating.score.5",
        ])
    }
}
