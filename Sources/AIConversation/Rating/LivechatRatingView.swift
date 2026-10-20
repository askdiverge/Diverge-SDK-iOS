//
//  LivechatRatingView.swift
//  AIConversation
//

import SwiftUI

/// The rating prompt for a livechat session that just ended: a 1–5 scale, then, for a score of 3
/// or lower, an optional comment. Send posts the score, with the comment when there is one; Skip
/// sends nothing on either step. The content scrolls, so large text never hides the buttons.
struct LivechatRatingView: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: RatingSubmissionModel
    let onSubmit: (_ score: Int, _ feedback: String?) -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: self.appearance.spacing.units(4)) {
                Text(L10n.ratingTitle)
                    .font(self.appearance.font(size: 17, weight: .bold))
                    .foregroundStyle(self.appearance.theme.primaryText)

                if let score = self.model.score, self.model.isFeedbackStep {
                    self.feedbackStep(score: score)
                } else {
                    self.scale
                }

                if let message = self.failureMessage {
                    Text(message)
                        .font(self.appearance.font(size: 12))
                        .foregroundStyle(self.appearance.theme.destructive)
                        .accessibilityIdentifier("livechat.rating.failed")
                }
            }
            .padding(self.appearance.spacing.units(5))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(self.appearance.theme.background)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(self.model.isSubmitting)
        .onChange(of: self.failureMessage) { _, message in
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

private extension LivechatRatingView {

    var failureMessage: String? {
        if case .failed(_, _, let message) = self.model.phase { message } else { nil }
    }

    var scale: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            // Stacks the scores when large text can't fit them in a row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: self.appearance.spacing.units(2)) {
                    self.scoreButtons
                }
                VStack(spacing: self.appearance.spacing.units(2)) {
                    self.scoreButtons
                }
            }
            self.skipButton
        }
    }

    var scoreButtons: some View {
        ForEach(1...5, id: \.self) { score in
            Button {
                // 4 and 5 need no comment, so they are sent at once.
                if !self.model.pick(score) {
                    self.onSubmit(score, nil)
                }
            } label: {
                AccentCapsuleLabel(
                    title: score.formatted(),
                    fillsWidth: true,
                    isBusy: self.model.isSubmitting && self.model.score == score
                )
            }
            .buttonStyle(.plain)
            .minimumTouchTarget()
            .disabled(self.model.isSubmitting)
            .accessibilityLabel(Text(L10n.ratingScore(score)))
            .accessibilityIdentifier("livechat.rating.score.\(score)")
        }
    }

    func feedbackStep(score: Int) -> some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
            Text(L10n.ratingFeedbackPrompt)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.secondaryText)

            TextField(L10n.ratingFeedbackPlaceholder.string, text: self.feedbackText, axis: .vertical)
                .lineLimit(3...6)
                .font(self.appearance.font(size: 15))
                .foregroundStyle(self.appearance.theme.inputText)
                .padding(self.appearance.spacing.units(3))
                .background(self.appearance.theme.inputBackground ?? self.appearance.theme.botSurface)
                .disabled(self.model.isSubmitting)
                .accessibilityIdentifier("livechat.rating.feedback")

            // Stacks the buttons when large text can't fit them in a row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: self.appearance.spacing.units(3)) {
                    self.sendButton(score: score)
                    self.skipButton
                }
                VStack(alignment: .leading, spacing: self.appearance.spacing.units(3)) {
                    self.sendButton(score: score)
                    self.skipButton
                }
            }
        }
    }

    /// Edits after a failed send go back to the comment step, keeping what was typed.
    var feedbackText: Binding<String> {
        Binding(
            get: { self.model.feedbackText },
            set: { text in
                self.model.editingAfterFailure()
                self.model.feedbackText = text
            }
        )
    }

    func sendButton(score: Int) -> some View {
        Button {
            self.onSubmit(score, self.model.feedbackText)
        } label: {
            AccentCapsuleLabel(title: L10n.ratingSend.string, isBusy: self.model.isSubmitting)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .disabled(self.model.isSubmitting)
        .accessibilityIdentifier("livechat.rating.send")
    }

    var skipButton: some View {
        Button(action: self.onSkip) {
            Text(L10n.ratingSkip)
                .font(self.appearance.font(size: 13, weight: .bold))
                .foregroundStyle(self.appearance.theme.secondaryText)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .disabled(self.model.isSubmitting)
        .accessibilityIdentifier("livechat.rating.skip")
    }
}
