//
//  ChatView+ViewModel+Send.swift
//  AIConversation
//

import Foundation
import AIConversationEngine

/// Message delivery, history paging, and the two session-ending operations (reset / delete).
extension ChatView.ViewModel {

    /// Sends a user message (draft text and any pending attachments). Recoverable failures
    /// (busy, retryable) bounce inline as a notice so the input stays stateless; a 401 ends
    /// the session and escapes as ``ChatView.SessionEnded`` for the view to alert on.
    func send() async throws(ChatView.SessionEnded) {
        let text = self.currentMessage
        let attachments = self.pendingAttachments
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !attachments.isEmpty else { return }

        self.currentMessage = ""
        self.pendingAttachments = []
        // The echo renders each photo from its data URL; hand the loader the bitmap we already
        // decoded so the user pane never round-trips base64 → ImageIO for its own upload.
        for pending in attachments {
            if let url = pending.attachment.dataURL {
                await self.imageLoader.store(pending.thumbnail, for: url)
            }
        }
        if let bounced = try await self.deliver(
            text,
            attachments: attachments.map(\.attachment)
        ) {
            self.currentMessage = bounced
            // A photo picked while the send was in flight is the newer intent; the bounced
            // ones go back in front of it and the cap trims from the oldest end.
            self.pendingAttachments = Self.capped(attachments + self.pendingAttachments)
        }
    }

    /// Sends a suggestion-card or start-prompt chip's text. Leaves the composer draft
    /// untouched — there is no draft to restore on a bounce, so recoverable failures only
    /// surface the existing notice.
    func send(prompt: String) async throws(ChatView.SessionEnded) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = try await self.deliver(text, attachments: [])
    }

    /// Shared delivery for composer and suggestion taps.
    /// Returns text to restore into the composer on a recoverable bounce; `nil` otherwise.
    /// Attachments are restored by the composer `send()` from its own captured copy.
    private func deliver(
        _ text: String,
        attachments: [OutgoingAttachment]
    ) async throws(ChatView.SessionEnded) -> String? {
        if self.notice?.edge == .bottom { self.dismissNotice() }
        guard let provider = self.provider else { return nil }

        do {
            try await provider.send(text, attachments: attachments)
            return nil

        } catch {
            switch error {
            case .busy(.streaming):
                self.presentNotice(Notice(edge: .bottom, message: L10n.noticeBusy.string, autoDismiss: .seconds(1)))
                return text

            case .busy(.operation):
                // A reset / delete is in flight (sub-second). Give the draft back rather than
                // drop a picked photo on the floor; the operation's own UI covers the wait.
                return text

            case .retry(popped: let lastMessage, body: let body):
                self.presentNotice(Notice(edge: .bottom, message: body ?? L10n.noticeSendFailed.string, autoDismiss: nil))
                return lastMessage

            case .conflict(popped: let popped):
                self.presentNotice(Notice(
                    edge: .bottom,
                    message: L10n.noticeSendFailed.string,
                    autoDismiss: nil
                ))
                return popped

            case .sessionExpired:
                throw ChatView.SessionEnded()
            }
        }
    }

    // MARK: History

    /// Loads the next older page of history. A recoverable failure is reported as
    /// ``HistoryLoadOutcome/failed`` rather than as a notice — the conversation list shows it
    /// inline at the top edge with a retry, where the reader is looking. A 401 ends the
    /// session and escapes as ``ChatView.SessionEnded`` for the view to alert on.
    @discardableResult
    func loadOlder() async throws(ChatView.SessionEnded) -> HistoryLoadOutcome {
        do {
            let prepended = try await self.provider?.loadOlder() ?? false
            return prepended ? .prepended : .nothing

        } catch ChatServiceError.sessionExpired {
            throw ChatView.SessionEnded()

        } catch is CancellationError {
            // The view's load task was torn down mid-flight; nothing to retry.
            return .nothing

        } catch let error as URLError where error.code == .cancelled {
            return .nothing

        } catch {
            return .failed
        }
    }

    // MARK: Reset / delete

    /// Resets the conversation.
    func reset() async {
        do {
            try await self.provider?.reset()
        } catch {
            // Provider leaves the conversation intact on failure — keep drafts so the
            // still-current chat can continue.
            self.presentNotice(Notice(
                edge: .bottom,
                message: L10n.noticeSendFailed.string,
                autoDismiss: .seconds(4)
            ))
            return
        }
        self.pendingAttachments = []
        self.currentMessage = ""
    }

    /// Request deletion of visitor data and end the session. Rethrows so the delete sheet can act on the
    /// hook's suspension point — success dismisses it, a failure leaves it open for the host.
    func delete() async throws(ChatView.DeletionFailed) {
        do {
            try await self.provider?.delete()
        } catch {
            throw ChatView.DeletionFailed()
        }
        self.pendingAttachments = []
        self.currentMessage = ""
    }
}
