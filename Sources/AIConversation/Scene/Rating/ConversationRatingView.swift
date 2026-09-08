//
//  ConversationRatingView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Close-rating overlay: pick 1–5, then (for scores ≤ 3) optional free-text feedback.
struct ConversationRatingView: View {

    @Environment(\.appearance) private var appearance

    @Bindable var model: RatingSubmissionModel
    var feedbackFocus: FocusState<Bool>.Binding
    let onSubmit: (Int, String?) -> Void
    /// Scale Skip / backdrop — dismiss without POSTing.
    let onSkip: () -> Void
    /// Feedback-step Skip — POST the score with no written feedback, then dismiss.
    let onSkipFeedback: (Int) -> Void

    private var theme: ChatAppearance.Theme { self.appearance.theme }
    private var spacing: ChatAppearance.Spacing { self.appearance.spacing }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.ratingTitle.string)
                .font(self.appearance.font(size: 17, weight: .bold))
                .foregroundStyle(self.theme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: self.spacing.units(11))
                .padding(.horizontal, self.spacing.units(2))
                .padding(.top, self.spacing.units(6))
                .accessibilityAddTraits(.isHeader)

            self.content
        }
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            self.footer
        }
        .background(self.theme.background)
        .disabled(self.model.isSubmitting)
        .scrollDismissesKeyboard(.interactively)
#if os(iOS)
        .toolbar {
            if self.feedbackFocus.wrappedValue {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.formDone.string) { self.feedbackFocus.wrappedValue = false }
                        .accessibilityIdentifier("form.done")
                }
            }
        }
#endif
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: self.spacing.units(4)) {
            switch self.model.phase {
            case .picking:
                self.pickingContent

            case .feedback(let score), .submitting(let score, _), .failed(let score, _, _):
                if score <= RatingSubmissionModel.feedbackThreshold {
                    self.feedbackContent(score: score)
                } else {
                    self.pickingContent
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, self.spacing.units(6))
        .padding(.top, self.spacing.units(2))
    }

    private var pickingContent: some View {
        VStack(alignment: .leading, spacing: self.spacing.units(4)) {
            Text(L10n.ratingMessage)
                .font(self.appearance.font(size: 15))
                .foregroundStyle(self.theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            RatingScaleView(isEnabled: !self.model.isSubmitting) { score in
                if self.model.pick(score) {
                    // Feedback step — stay on the overlay.
                } else {
                    self.onSubmit(score, nil)
                }
            }

            if case .failed(_, _, let message) = self.model.phase {
                Text(message)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.theme.destructive)
                    .accessibilityIdentifier("rating.error")
            }
        }
    }

    private func feedbackContent(score: Int) -> some View {
        VStack(alignment: .leading, spacing: self.spacing.units(3)) {
            HStack {
                Text("\(score)")
                    .font(self.appearance.font(size: 15, weight: .bold))
                    .foregroundStyle(self.theme.accentForeground)
                    .frame(width: self.spacing.units(8), height: self.spacing.units(8))
                    .background(ChatAppearance.Theme.ratingColor(for: score), in: Circle())
                    .accessibilityLabel(RatingScaleView.label(for: score))

                Text(L10n.ratingFeedbackTitle)
                    .font(self.appearance.font(size: 17, weight: .bold))
                    .foregroundStyle(self.theme.primaryText)
            }

            TextField(
                L10n.ratingFeedbackPlaceholder.string,
                text: self.$model.feedbackText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .focused(self.feedbackFocus)
            .lineLimit(3...6)
            .font(self.appearance.font(size: 15))
            .foregroundStyle(self.theme.inputText)
            .padding(self.spacing.units(2))
            .background(self.theme.inputBackground ?? self.theme.background)
            .border(self.theme.inputBorder ?? self.theme.outline, width: 1)
            .accessibilityIdentifier("rating.feedback")
            .onChange(of: self.model.feedbackText) { _, _ in
                self.model.editingAfterFailure()
            }
#if os(iOS)
            .submitLabel(.done)
            .onSubmit { self.feedbackFocus.wrappedValue = false }
#endif

            if case .failed(_, _, let message) = self.model.phase {
                Text(message)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.theme.destructive)
                    .accessibilityIdentifier("rating.error")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: self.spacing.units(2)) {
            Button(action: self.skip) {
                Text(L10n.ratingSkip)
                    .font(self.appearance.font(size: 13, weight: .bold))
                    .foregroundStyle(self.theme.primaryText)
                    .padding(self.spacing.units(4))
                    .frame(maxWidth: .infinity)
                    .border(self.theme.outline, width: 1)
                    .frame(minHeight: self.spacing.units(11))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rating.skip")
            .accessibilityHint(
                self.model.isFeedbackStep
                    ? L10n.ratingSkipFeedbackHint.string
                    : L10n.ratingSkipHint.string
            )
            .disabled(self.model.isSubmitting)

            if self.model.isFeedbackStep, let score = self.model.score {
                self.submitButton(score: score)
            }
        }
        .padding([.top, .horizontal], self.spacing.units(6))
        .padding(.bottom, self.spacing.units(4))
        .background(self.theme.background)
    }

    private func skip() {
        self.feedbackFocus.wrappedValue = false
        if self.model.isFeedbackStep, let score = self.model.score {
            self.onSkipFeedback(score)
        } else {
            self.onSkip()
        }
    }

    private func submitButton(score: Int) -> some View {
        Button {
            self.feedbackFocus.wrappedValue = false
            let text = self.model.feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.onSubmit(score, text.isEmpty ? nil : text)
        } label: {
            AccentCapsuleLabel(
                title: L10n.ratingFeedbackSubmit.string,
                fillsWidth: true,
                isBusy: self.model.isSubmitting
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rating.submit")
        .accessibilityLabel(L10n.ratingFeedbackSubmit.string)
        .disabled(self.model.isSubmitting)
    }
}
