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
package actor ChatProvider: ChatProviding {

    package typealias ChatStream = AsyncStream<ConversationSnapshot>

    private let service: any ChatServicing
    private let pageContext: @Sendable () async -> String?

    /// yield new chat conversations
    private let continuation: ChatStream.Continuation

    /// Synthetic greeting from config — a plain string, wrapped into a `ChatResponse`
    /// Pinned as the first `incoming`
    /// Re-seeded on `clear()` so it survives reset.
    private let welcomeMessage: String?

    /// Right pane — committed user turns. Outer = turns, inner = adjacent bubbles.
    /// Built through the same rich_text parse as `incoming`; user text just lands
    /// unstyled. One parser, not two.
    private var user: [Identified<[AttributedString]>] = []

    /// Left pane — committed turns from every non-user role (assistant, agent,
    /// system) folded together, as display models.
    private var incoming: [Identified<[ChatResponse]>] = []

    /// Owns the history cursor and serializes pagination — no overlapping loads.
    private var paginator = Paginator()

    /// The turn whose reply is streaming
    /// and the marker the snapshot carries so the view can flag that a turn is live.
    /// Set before the first suspension in `send`, cleared when the stream settles.
    private var streamingTurnID: UUID?

    /// Serializes send/reset/delete — they must not interleave.
    private var isBusy = false

    /// Snapshot channel the view model observes. Latest-wins — the VM only ever
    /// cares about the current conversation, never a backlog.
    package let stream: ChatStream

    package init(
        service: any ChatServicing,
        pageContext: @escaping @Sendable () async -> String?,
        welcomeMessage: String? = nil
    ) {
        self.service = service
        self.pageContext = pageContext
        self.welcomeMessage = welcomeMessage
        (self.stream, self.continuation) = ChatStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// True only while the synthetic welcome is present (history exhausted). It sits above the
    /// first user turn, so the bot leads the interleave,
    /// otherwise the user leads.
    private var showsWelcome: Bool {
        self.welcomeMessage != nil && self.paginator.isExhausted
    }

    private func publish() {
        self.continuation.yield(
            .init(
                user: self.user,
                incoming: self.incoming,
                isUserInitiatedConversation: !self.showsWelcome,
                streamingTurnID: self.streamingTurnID
            )
        )
    }

    /// The snapshot stream lives for the whole session and is never finished mid-flight
    /// releasing the provider is its only terminator.
    deinit {
        self.continuation.finish()
    }
}

extension ChatProvider {

    /// Sends a user message and folds the streamed reply into the conversation.
    package func send(_ text: String) async throws(SendFailure) {
        // Single-flight — reject a send while a reply is already streaming.
        guard !self.isBusy else { throw .busy(self.streamingTurnID != nil ? .streaming : .operation) }

        self.isBusy = true
        defer { self.isBusy = false }

        // Mint the in-flight turn and mark it live before the first suspension, so concurrent
        // sends bounce and the view can flag exactly this turn from the snapshot.
        let inFlight = Identified<[ChatResponse]>(model: [.placeholder(AttributedString("• • •"))])
        self.streamingTurnID = inFlight.id

        // Extra context
        let page = await self.pageContext()

        // Optimistic echo — the user turn shows immediately.
        self.user.append(Identified(model: [AttributedString(text)]))
        self.publish()

        // In-flight assistant turn, the thinking placeholder fills the pre-delta gap
        // the first streamed response overwrites index 0. Dropped on failure.
        self.incoming.append(inFlight)

        // Reveal placeholder only if the reply is slow enough to warrant it — a fast
        // reply overwrites index 0 before this fires
        let reveal = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.publish()
        }

        defer { reveal.cancel() }

        var buffer = DeltaBuffer { Self.response(for: $0) }

        do {
            for try await event in self.service.sendMessage(text, page: page) {
                self.apply(event, into: &buffer)
            }
            // Stream finished, clear the live marker.
            // A content-less reply never overwrote the placeholder, so drop that dangling turn
            // either way publish so the stop signal a snapshot change.
            self.streamingTurnID = nil
            if case .placeholder? = self.incoming.last?.model.first {
                self.incoming.removeLast()
            }
            self.publish()

        } catch ChatServiceError.sessionExpired {
            self.clear()
            self.publish()
            throw SendFailure.sessionExpired

        } catch ChatServiceError.stream(let error) {
            let popped = self.discardInFlight()
            self.publish()
            throw .retry(popped: popped, body: error.message)

        } catch {
            let popped = self.discardInFlight()
            self.publish()
            throw .retry(popped: popped, body: nil)
        }
    }

    private func apply(_ event: StreamEvent, into buffer: inout DeltaBuffer) {
        switch event {
        case .delta(_, let delta):
            buffer.append(delta)
            guard let preview = buffer.render() else { return }
            self.place(preview, at: buffer.commitCount)
            self.publish()

        case .part(let part):
            // Authoritative — replace the part's preview, then advance.
            guard
                let response = Self.incoming(part)
            else {
                // Unsupported part renders nothing, reset without consuming index.
                buffer.reset()
                return
            }

            self.place(response, at: buffer.commitCount)
            buffer.commit()
            self.publish()

        case .status, .done, .error, .unknown:
            // .status is lifecycle only,
            // .done is terminal.
            // .error is routed to the throwing channel.
            // .unknown ignored.
            return
        }
    }

    /// Loads the next older page of history and prepends it. No-op when a load is
    /// already in flight or no pages remain. Drives both the first load and refresh.
    package func loadOlder() async throws {
        do {
            let cursor = try self.paginator.next()
            let page = try await self.service.fetchHistory(cursor: cursor)
            self.paginator.commit(nextCursor: page.nextCursor)
            self.prepend(page.messages)
            self.publish()

        } catch Paginator.Failure.busy {
            // In progress, do nothing
        } catch Paginator.Failure.exhausted {
            // No more history available, do nothing
        } catch ChatServiceError.sessionExpired {
            self.clear()
            self.publish()
            throw ChatServiceError.sessionExpired

        } catch {
            self.paginator.release()
            throw error
        }
    }

    /// Rotates the session and clears the conversation.
    /// Throws on failure so the caller can revert the control and surface the error.
    /// Opportunistically loads history for new session.
    /// If the rotation fails the conversation is left intact.
    package func reset() async throws {
        guard !self.isBusy else { throw SendFailure.busy(self.streamingTurnID != nil ? .streaming : .operation) }
        self.isBusy = true
        defer { self.isBusy = false }

        try await self.service.resetConversation()
        self.clear()
        do {
            try await self.loadOlder()
        } catch {
            self.publish()
        }
    }

    /// Wipes visitor data and ends the session, clearing the conversation.
    /// Throws on failure so the caller can revert the control and surface the error.
    /// a failed delete leaves the conversation intact.
    package func delete() async throws {
        guard !self.isBusy else { throw SendFailure.busy(self.streamingTurnID != nil ? .streaming : .operation) }
        self.isBusy = true
        defer { self.isBusy = false }

        try await self.service.deleteData()
        self.clear()
        self.publish()
    }
}

private extension ChatProvider {

    /// Places a response  at `index` in the assistant turn
    /// appends it on the chunck or  replaces it as the part streams in.
    func place(_ response: ChatResponse, at index: Int) {
        let turn = self.incoming.count - 1
        var responses = self.incoming[turn].model
        if index < responses.count {
            responses[index] = response
        } else {
            responses.append(response)
        }
        self.incoming[turn] = Identified(id: self.incoming[turn].id, model: responses)
    }

    /// Discards the unfinished assistant reply and pops the user echo, returning its text
    /// for the caller to restore to the input.
    func discardInFlight() -> String {
        self.streamingTurnID = nil
        self.incoming.removeLast()
        let userText = self.user.removeLast().model.last ?? ""
        return String(userText.characters)
    }

    /// Drops all conversation state and resets pagination — after a successful reset
    /// or delete the next session starts clean (the welcome is re-seeded).
    func clear() {
        self.user = []
        self.incoming = []
        self.paginator = Paginator()
        self.streamingTurnID = nil
    }

    /// Buckets a history page into the two panes and prepends it (older turns go
    /// above existing ones). One message becomes one turn; its parts become the
    /// turn's adjacent bubbles. Selecting the parser for each part is the caller's
    /// job here — `RichTextParser` only ever sees a `RichText`.
    func prepend(_ messages: [Message]) {
        var olderUser: [Identified<[AttributedString]>] = []
        var olderIncoming: [Identified<[ChatResponse]>] = []

        // reverse to chronological (oldest → newest).
        for message in messages.reversed() {
            if message.role == .user {
                olderUser.append(Identified(model: message.parts.compactMap(Self.user)))
            } else {
                olderIncoming.append(Identified(model: message.parts.compactMap(Self.incoming)))
            }
        }

        self.user.insert(contentsOf: olderUser, at: 0)
        self.incoming.insert(contentsOf: olderIncoming, at: 0)

        // Once history is exhausted this is the true start — pin the synthetic greeting above it.
        if self.showsWelcome, let welcome = self.welcomeMessage {
            self.incoming.insert(Identified(model: [.text(AttributedString(welcome))]), at: 0)
        }
    }

    static func user(_ part: Part) -> AttributedString? {
        switch part {
        case .richText(let richText): RichTextParser.attributedText(richText)
        default: nil // user turns should only ever carry text
        }
    }

    static func incoming(_ part: Part) -> ChatResponse? {
        switch part {
        case .richText(let richText):
            RichTextParser.attributedText(richText).map(ChatResponse.text)
        case .products(let products):
                .products(products.products)
        case .table(let table):
                .table(
                    TableMapper.content(
                        caption: table.caption,
                        headers: table.headers,
                        alignments: table.alignments,
                        rows: table.rows
                    )
                )
        case .unknown: nil
        }
    }

    /// Renders the in-flight part's accumulated deltas to a preview, dispatched on the
    /// part type (the first delta carries it).
    static func response(for deltas: [PartDelta]) -> ChatResponse? {
        switch deltas.first {
        case .richText:
            return RichTextParser.attributedText(
                deltas.compactMap {
                    guard case .richText(let richText) = $0 else { return nil }
                    return richText
                }
            ).map(ChatResponse.text)

        case .products:
            let cards = deltas.compactMap { delta -> Products.Card? in
                guard case .products(.appendProduct(let card)) = delta else { return nil }
                return card
            }

            return cards.isEmpty ? nil : .products(cards)

        case .table:
            return TableMapper.content(
                deltas.compactMap {
                    guard case .table(let table) = $0 else { return nil }
                    return table
                }
            ).map(ChatResponse.table)

        case .endPart, .unknown, .none:
            return nil
        }
    }
}
