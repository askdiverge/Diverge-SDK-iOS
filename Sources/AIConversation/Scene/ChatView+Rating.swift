//
//  ChatView+Rating.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

extension ChatView {

    /// Close: skip a visible livechat CSAT overlay (no POST) then `onClose`; otherwise last-chance
    /// CSAT when closed + pending; otherwise conversation `/rate`; otherwise `onClose`.
    func requestClose() {
        self.inputFocused = false
        self.focusedFormField = nil
        self.ratingFeedbackFocused = false
        switch self.viewModel.prepareClose(
            showingLivechatCSAT: self.ratingSheet?.context == .livechatClosed
        ) {
        case .handoffToHost:
            self.ratingSheet = nil
            self.viewModel.onClose?()
        case .presentLivechatCSAT:
            self.presentLivechatCSATIfNeeded()
        case .presentConversationRating:
            self.ratingSheet = RatingSheetToken(
                model: self.viewModel.beginRating(),
                context: .conversationClose
            )
        }
    }

    /// Scale Skip and backdrop tap.
    /// Conversation: dismiss without POSTing, then `onClose`.
    /// Livechat CSAT: dismiss without POSTing, stay in chat.
    func skipRating() {
        self.ratingFeedbackFocused = false
        let context = self.ratingSheet?.context ?? .conversationClose
        self.ratingSheet = nil
        self.viewModel.endRating()
        switch context {
        case .conversationClose:
            self.viewModel.onClose?()
        case .livechatClosed:
            self.viewModel.dismissLivechatCSAT()
        }
    }

    func submitRating(score: Int, feedback: String?) {
        self.ratingFeedbackFocused = false
        let context = self.ratingSheet?.context ?? .conversationClose
        Task {
            switch context {
            case .conversationClose:
                await self.submitConversationRating(score: score, feedback: feedback)
            case .livechatClosed:
                await self.submitLivechatCSAT(score: score, feedback: feedback)
            }
        }
    }

    private func submitConversationRating(score: Int, feedback: String?) async {
        do {
            try await self.viewModel.submitRating(score: score, feedback: feedback)
            // Non-401 failures return without throwing and leave `hasRated` false so the
            // overlay stays for retry — only dismiss after a successful submit.
            guard self.viewModel.ratingSessionHasRated else { return }
            self.ratingSheet = nil
            self.viewModel.onClose?()
        } catch {
            self.ratingSheet = nil
            self.viewModel.onClose?()
            self.showSessionEndedAlert = true
        }
    }

    private func submitLivechatCSAT(score: Int, feedback: String?) async {
        do {
            try await self.viewModel.submitLivechatFeedback(score: score, feedback: feedback)
            // Success (including 409 already-submitted) clears `ratingModel`.
            guard self.viewModel.ratingModel == nil else { return }
            self.ratingSheet = nil
        } catch {
            self.ratingSheet = nil
            self.viewModel.dismissLivechatCSAT()
            self.showSessionEndedAlert = true
        }
    }

    /// Presents the livechat CSAT overlay when the poller reports closed + pending feedback.
    func presentLivechatCSATIfNeeded() {
        guard self.viewModel.livechatCSATPending else { return }
        guard self.ratingSheet == nil else { return }
        self.ratingSheet = RatingSheetToken(
            model: self.viewModel.beginRating(),
            context: .livechatClosed
        )
        self.viewModel.consumeLivechatCSATPending()
    }

    /// Waiting/active started under a livechat CSAT overlay — drop the card (no POST).
    /// The view model already cleared the draft via ``ChatView.ViewModel/resetLivechatCSATDismiss()``.
    func dismissLivechatCSATOverlayIfPresented() {
        guard self.ratingSheet?.context == .livechatClosed else { return }
        self.ratingFeedbackFocused = false
        self.ratingSheet = nil
    }
}
