//
//  ConversationRatingSheet.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Token that presents the rating overlay. A nested `.sheet` on `ChatView` never surfaces
/// when the host already presents the chat in a sheet (Sample's pattern), so this is an
/// overlay card, not `sheet(item:)`.
struct RatingSheetToken: Identifiable {

    enum Context: Equatable {
        /// Chat Close — POST `/rate`, then `onClose`.
        case conversationClose
        /// Livechat session closed with `feedback.pending` — POST `/livechat/feedback`, stay in chat.
        case livechatClosed
    }

    let id = UUID()
    let model: RatingSubmissionModel
    let context: Context

    init(model: RatingSubmissionModel, context: Context = .conversationClose) {
        self.model = model
        self.context = context
    }
}

/// Overlay card for the close-rating prompt.
///
/// Hides the conversation from VoiceOver while presented so the rotor cannot walk the chat
/// under the dimming view. Scale Skip and a backdrop tap dismiss without POSTing; Skip on
/// the feedback step submits the score with no written feedback (web `handleFeedbackSkip`).
struct ConversationRatingSheetModifier: ViewModifier {

    @Binding var token: RatingSheetToken?
    var feedbackFocus: FocusState<Bool>.Binding
    let onSubmit: (Int, String?) -> Void
    let onSkip: () -> Void
    let onSkipFeedback: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(self.token != nil)
            .overlay {
                if let token {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture {
                                guard !token.model.isSubmitting else { return }
                                self.onSkip()
                            }
                            .accessibilityHidden(true)

                        VStack {
                            Spacer(minLength: 0)
                            ConversationRatingView(
                                model: token.model,
                                feedbackFocus: self.feedbackFocus,
                                onSubmit: self.onSubmit,
                                onSkip: self.onSkip,
                                onSkipFeedback: self.onSkipFeedback
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape) {
                                guard !token.model.isSubmitting else { return }
                                self.onSkip()
                            }
                        }
                    }
                    .transition(.opacity)
                    .accessibilityHidden(false)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: self.token?.id)
    }
}
