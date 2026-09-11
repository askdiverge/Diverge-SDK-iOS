//
//  ChatProvider.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-11.
//

import Foundation

/// Stateful session data layer between the facade (`ChatServicing`, pure wire I/O)
/// and the view model.
/// Owns the conversation and the streaming lifecycle.
///
/// Sibling extension files hold the rest: `+Session` (history paging, reset / delete / export),
/// `+Turns` (in-place turn mutations) and `+Mapping` (wire part → display model). State is
/// declared here and is actor-internal so those extensions can reach it.
package actor ChatProvider: ChatProviding {

    package typealias ChatStream = AsyncStream<ConversationSnapshot>

    let service: any ChatServicing
    let pageContext: @Sendable () async -> String?

    /// yield new chat conversations
    let continuation: ChatStream.Continuation

    /// Synthetic greeting from config — a plain string, wrapped into a `ChatResponse`
    /// Pinned as the first turn when history is exhausted.
    /// Re-seeded on `clear()` so it survives reset.
    let welcomeMessage: String?

    /// Whether `request_image_upload` markers render. Off when the host disabled attachments:
    /// the marker then maps to nothing at ingestion, so a marker-only message produces no turn
    /// (rather than an empty row) and the UI needs no gate of its own.
    let acceptsImageUploadPrompts: Bool

    /// Chronological conversation — oldest first. User and non-user roles share one list so
    /// history pages that do not strictly alternate still render in wire order.
    var turns: [Identified<ConversationSnapshot.Turn>] = []

    /// Newest local send echo — published for the top-flowing layout; never set by prepend.
    var lastSentUserTurnID: UUID?

    /// Owns the history cursor and serializes pagination — no overlapping loads.
    var paginator = Paginator()

    /// The turn whose reply is streaming
    /// and the marker the snapshot carries so the view can flag that a turn is live.
    /// Set before the first suspension in `send`, cleared when the stream settles.
    var streamingTurnID: UUID?

    /// Serializes send/reset/delete — they must not interleave.
    var isBusy = false

    /// Snapshot channel the view model observes. Latest-wins — the VM only ever
    /// cares about the current conversation, never a backlog.
    nonisolated package let stream: ChatStream

    package init(
        service: any ChatServicing,
        pageContext: @escaping @Sendable () async -> String?,
        welcomeMessage: String? = nil,
        acceptsImageUploadPrompts: Bool = true
    ) {
        self.service = service
        self.pageContext = pageContext
        self.welcomeMessage = welcomeMessage
        self.acceptsImageUploadPrompts = acceptsImageUploadPrompts
        let pair = ChatStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    /// True only while the synthetic welcome is present (history exhausted).
    var showsWelcome: Bool {
        self.welcomeMessage != nil && self.paginator.isExhausted
    }

    func publish() {
        self.continuation.yield(
            .init(
                turns: self.turns,
                streamingTurnID: self.streamingTurnID,
                canLoadOlder: !self.paginator.isExhausted,
                lastSentUserTurnID: self.lastSentUserTurnID
            )
        )
    }

    /// The snapshot stream lives for the whole session and is never finished mid-flight
    /// releasing the provider is its only terminator.
    deinit {
        self.continuation.finish()
    }
}

// MARK: - Send

extension ChatProvider {

    /// Sends a user message (text and/or attachments) and folds the streamed reply into the
    /// conversation.
    package func send(_ text: String, attachments: [OutgoingAttachment] = []) async throws(SendFailure) {
        // Single-flight — reject a send while a reply is already streaming.
        guard !self.isBusy else { throw .busy(self.streamingTurnID != nil ? .streaming : .operation) }

        self.isBusy = true
        defer { self.isBusy = false }

        // Mint both turns before the first suspension — the in-flight one is marked live so
        // concurrent sends bounce and the view can flag exactly this turn from the snapshot; the
        // echo keeps its id so a failed send removes exactly it, never "the last user turn".
        let echo = Identified(model: ConversationSnapshot.Turn.user(Self.echo(text: text, attachments: attachments)))
        let inFlight = Identified(model: ConversationSnapshot.Turn.bot([.placeholder(AttributedString("• • •"))]))
        self.streamingTurnID = inFlight.id

        // Extra context
        let page = await self.pageContext()

        // Optimistic echo — the user turn shows immediately (text + any pending media).
        self.turns.append(echo)
        self.lastSentUserTurnID = echo.id
        self.publish()

        // In-flight assistant turn, the thinking placeholder fills the pre-delta gap
        // the first streamed response overwrites index 0. Dropped on failure.
        self.turns.append(inFlight)

        // Reveal placeholder only if the reply is slow enough to warrant it — a fast
        // reply overwrites index 0 before this fires
        let reveal = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.publish()
        }

        defer { reveal.cancel() }

        var buffer = DeltaBuffer { Self.response(for: $0) }
        var finalMessage: Message?

        do {
            for try await event in self.service.sendMessage(text, attachments: attachments, page: page) {
                self.apply(event, into: &buffer, finalMessage: &finalMessage)
            }
            // Clear the live marker before reconciling so a content swap does not re-trigger
            // streaming chrome (typewriter / thinking border) on an already-finished turn.
            // `done` is the only path for parts that never stream (image, file); if it is
            // absent or empty, fall back to dropping a never-overwritten placeholder.
            self.streamingTurnID = nil
            if !self.reconcile(finalMessage, turnID: inFlight.id) {
                self.dropUnfilledPlaceholder(turnID: inFlight.id)
            }
            self.publish()

        } catch ChatServiceError.sessionExpired {
            self.clear()
            self.publish()
            throw SendFailure.sessionExpired

        } catch ChatServiceError.conflict {
            // Server rejected the send as conflicting — pop the AI placeholder + echo so the
            // VM can restore the text for retry.
            let popped = self.discardInFlight(echoID: echo.id)
            self.publish()
            throw .conflict(popped: popped)

        } catch ChatServiceError.stream(let error) {
            let popped = self.discardInFlight(echoID: echo.id)
            self.publish()
            throw .retry(popped: popped, body: error.message)

        } catch {
            let popped = self.discardInFlight(echoID: echo.id)
            self.publish()
            throw .retry(popped: popped, body: nil)
        }
    }

    private func apply(
        _ event: StreamEvent,
        into buffer: inout DeltaBuffer,
        finalMessage: inout Message?
    ) {
        switch event {
        case .delta(_, let delta):
            buffer.append(delta)
            guard let preview = buffer.render() else { return }
            self.place(preview, at: buffer.commitCount)
            self.publish()

        case .part(let part):
            // Authoritative — replace the part's preview, then advance.
            guard
                let response = self.incoming(part)
            else {
                // Unsupported part renders nothing, reset without consuming index.
                buffer.reset()
                return
            }

            self.place(response, at: buffer.commitCount)
            buffer.commit()
            self.publish()

        case .done(let message, _):
            // Terminal — capture for post-stream reconciliation. Image and file parts only
            // appear here (and in history), never as streaming `part` events. The visitor
            // token riding along is the service's business and was adopted before we saw it.
            finalMessage = message

        case .status, .error, .unknown:
            // .status is lifecycle only,
            // .error is routed to the throwing channel,
            // .unknown ignored.
            return
        }
    }
}
