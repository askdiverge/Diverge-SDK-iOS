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
    /// Pinned as the first turn when history is exhausted.
    /// Re-seeded on `clear()` so it survives reset.
    private let welcomeMessage: String?

    /// Whether `request_image_upload` markers render. Off when the host disabled attachments:
    /// the marker then maps to nothing at ingestion, so a marker-only message produces no turn
    /// (rather than an empty row) and the UI needs no gate of its own.
    private let acceptsImageUploadPrompts: Bool

    /// Whether `request_human_agent` markers render. Off when livechat is disabled or offline.
    private let acceptsHumanAgentPrompts: Bool

    /// Livechat message ids already shown (optimistic echo + poll). Prevents double-rendering.
    private var ingestedLivechatMessageIDs: Set<String> = []
    /// While a livechat send is in flight, poll ticks are queued and replayed after the POST
    /// records its id — otherwise the poll can double-render the visitor's own message.
    private var livechatSendInFlight = false
    private var deferredLivechatMessages: [LivechatMessage] = []

    /// Chronological conversation — oldest first. User and non-user roles share one list so
    /// history pages that do not strictly alternate still render in wire order.
    private var turns: [Identified<ConversationSnapshot.Turn>] = []

    /// Newest local send echo — published for the top-flowing layout; never set by prepend.
    private var lastSentUserTurnID: UUID?

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
    nonisolated package let stream: ChatStream

    package init(
        service: any ChatServicing,
        pageContext: @escaping @Sendable () async -> String?,
        welcomeMessage: String? = nil,
        acceptsImageUploadPrompts: Bool = true,
        acceptsHumanAgentPrompts: Bool = true
    ) {
        self.service = service
        self.pageContext = pageContext
        self.welcomeMessage = welcomeMessage
        self.acceptsImageUploadPrompts = acceptsImageUploadPrompts
        self.acceptsHumanAgentPrompts = acceptsHumanAgentPrompts
        let pair = ChatStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    /// True only while the synthetic welcome is present (history exhausted).
    private var showsWelcome: Bool {
        self.welcomeMessage != nil && self.paginator.isExhausted
    }

    private func publish() {
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
                if let index = self.turns.lastIndex(where: { $0.id == inFlight.id }),
                   case .bot(let responses) = self.turns[index].model,
                   case .placeholder? = responses.first {
                    self.turns.remove(at: index)
                }
            }
            self.publish()

        } catch ChatServiceError.sessionExpired {
            self.clear()
            self.publish()
            throw SendFailure.sessionExpired

        } catch ChatServiceError.conflict {
            // Active livechat owns the channel — pop the AI placeholder + echo so the VM can
            // re-route the same text through `/livechat/messages`.
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

    /// Loads the next older page of history and prepends it. No-op when a load is
    /// already in flight or no pages remain. Drives both the first load and refresh.
    /// Returns whether the snapshot gained turns, so a caller holding a scroll anchor knows
    /// whether a prepend is about to land or nothing moved. A non-empty page can still report
    /// `false` when none of its messages render.
    @discardableResult
    package func loadOlder() async throws -> Bool {
        do {
            let cursor = try self.paginator.next()
            let page = try await self.service.fetchHistory(cursor: cursor)
            self.paginator.commit(nextCursor: page.nextCursor)
            let prepended = self.prepend(page.messages)
            self.publish()
            return prepended

        } catch Paginator.Failure.busy {
            // In progress, do nothing
            return false
        } catch Paginator.Failure.exhausted {
            // No more history available, do nothing
            return false
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

    /// Fetches the visitor's GDPR export JSON without clearing the session.
    package func exportMyData() async throws(ChatServiceError) -> Data {
        try await self.service.exportMyData()
    }

    /// Appends livechat messages from a poll or send response. Skips ids already ingested
    /// (optimistic echo reconciliation). Maps roles onto `.user` / `.agent` / `.bot` turns.
    /// Queues `.user` (and everything else) while a send is in flight so the POST id is
    /// recorded before the poll of that same row can mint a second turn.
    package func appendLivechat(_ messages: [LivechatMessage]) {
        if self.livechatSendInFlight {
            self.deferredLivechatMessages.append(contentsOf: messages)
            return
        }
        self.ingestLivechat(messages)
    }

    /// Drops local conversation state after a 401 detected outside send (livechat poller).
    package func expireSession() {
        self.clear()
        self.publish()
    }

    /// Appends a session-local boundary note (queue / agent joined / ended).
    package func note(_ note: LivechatNote) {
        self.turns.append(Identified(model: .note(note)))
        self.publish()
    }

    /// Sends on `POST /livechat/messages` while the session is active. Optimistic user echo;
    /// the POST response id is recorded so the next poll cannot double-render it.
    package func sendLivechat(
        _ text: String,
        attachments: [OutgoingAttachment] = []
    ) async throws(SendFailure) {
        guard !self.isBusy else { throw .busy(self.streamingTurnID != nil ? .streaming : .operation) }
        self.isBusy = true
        defer { self.isBusy = false }

        let echo = Identified(model: ConversationSnapshot.Turn.user(Self.echo(text: text, attachments: attachments)))
        self.turns.append(echo)
        self.lastSentUserTurnID = echo.id
        self.publish()

        self.livechatSendInFlight = true
        defer {
            self.livechatSendInFlight = false
            let deferred = self.deferredLivechatMessages
            self.deferredLivechatMessages = []
            if !deferred.isEmpty {
                self.ingestLivechat(deferred)
            }
        }

        let page = await self.pageContext()

        do {
            let stored = try await self.service.sendLivechatMessage(text, attachments: attachments, page: page)
            self.ingestedLivechatMessageIDs.insert(stored.messageId)
            self.publish()
        } catch ChatServiceError.sessionExpired {
            self.clear()
            self.publish()
            throw SendFailure.sessionExpired
        } catch ChatServiceError.conflict {
            self.popEcho(echo.id)
            throw .livechatInactive(popped: text)
        } catch {
            self.popEcho(echo.id)
            throw .retry(popped: text, body: nil)
        }
    }
}

private extension ChatProvider {

    func ingestLivechat(_ messages: [LivechatMessage]) {
        var didChange = false
        for message in messages {
            guard self.ingestedLivechatMessageIDs.insert(message.messageId).inserted else { continue }
            switch message.role {
            case .user:
                let contents = message.parts.compactMap(Self.user)
                guard !contents.isEmpty else { continue }
                self.turns.append(Identified(model: .user(contents)))
                didChange = true
            case .agent:
                let responses = message.parts.compactMap { self.incoming($0) }
                guard !responses.isEmpty else { continue }
                // Empty displayName — the UI substitutes the localised "Agent" fallback.
                let identity = message.agent
                    ?? LivechatAgent(agentId: "unknown", displayName: "")
                self.turns.append(Identified(model: .agent(identity, responses)))
                didChange = true
            case .system:
                let responses = message.parts.compactMap { self.incoming($0) }
                guard !responses.isEmpty else { continue }
                self.turns.append(Identified(model: .system(responses)))
                didChange = true
            default:
                let responses = message.parts.compactMap { self.incoming($0) }
                guard !responses.isEmpty else { continue }
                self.turns.append(Identified(model: .bot(responses)))
                didChange = true
            }
        }
        if didChange { self.publish() }
    }

    func popEcho(_ echoID: UUID) {
        if let index = self.turns.lastIndex(where: { $0.id == echoID }) {
            self.turns.remove(at: index)
        }
        self.clearSentEcho(echoID)
        self.publish()
    }

    /// Places a response at `index` in the streaming assistant turn — appends it on the chunk
    /// or replaces it as the part streams in. Looked up by ``streamingTurnID`` so the turn stays
    /// reachable once the conversation is a single interleaved list.
    func place(_ response: ChatResponse, at index: Int) {
        guard
            let turnID = self.streamingTurnID,
            let turnIndex = self.turns.lastIndex(where: { $0.id == turnID }),
            case .bot(var responses) = self.turns[turnIndex].model
        else { return }

        if index < responses.count {
            responses[index] = response
        } else {
            responses.append(response)
        }
        self.turns[turnIndex] = Identified(id: turnID, model: .bot(responses))
    }

    /// Swaps the turn identified by `turnID` for the authoritative `done` message — the only path
    /// by which parts that never stream (image, file) reach the conversation. Persisted order
    /// wins over streamed order. Returns false when there is no message, the turn is gone, or
    /// the message renders nothing, leaving the caller's placeholder cleanup to run.
    func reconcile(_ message: Message?, turnID: UUID) -> Bool {
        guard let message, let turn = self.turns.lastIndex(where: { $0.id == turnID }) else {
            return false
        }
        let responses = message.parts.compactMap { self.incoming($0) }
        guard !responses.isEmpty else { return false }
        self.turns[turn] = Identified(id: turnID, model: .bot(responses))
        return true
    }

    /// Discards the unfinished assistant reply and pops the user echo, returning its text
    /// for the caller to restore to the input. Attachments are restored from the view model's
    /// own copy — only the last `.text` bubble is returned here. Both turns are removed by id, so
    /// a history page landing mid-stream (or, later, an agent turn) cannot shift the target.
    func discardInFlight(echoID: UUID) -> String {
        if let turnID = self.streamingTurnID,
           let index = self.turns.lastIndex(where: { $0.id == turnID }) {
            self.turns.remove(at: index)
        }
        self.streamingTurnID = nil

        defer { self.clearSentEcho(echoID) }

        guard
            let index = self.turns.lastIndex(where: { $0.id == echoID }),
            case .user(let contents) = self.turns.remove(at: index).model
        else { return "" }

        for content in contents.reversed() {
            if case .text(let text) = content {
                return String(text.characters)
            }
        }
        return ""
    }

    /// Drops the send-arm id when that optimistic echo is gone (failed send / livechat pop).
    func clearSentEcho(_ echoID: UUID) {
        if self.lastSentUserTurnID == echoID {
            self.lastSentUserTurnID = nil
        }
    }

    /// Drops all conversation state and resets pagination — after a successful reset
    /// or delete the next session starts clean (the welcome is re-seeded).
    func clear() {
        self.turns = []
        self.paginator = Paginator()
        self.streamingTurnID = nil
        self.lastSentUserTurnID = nil
        self.ingestedLivechatMessageIDs = []
        self.livechatSendInFlight = false
        self.deferredLivechatMessages = []
    }

    /// Maps a history page onto ordered turns and prepends it (older turns go above existing
    /// ones). Wire order is preserved — one message becomes one turn; its parts become the
    /// turn's adjacent bubbles. Selecting the parser for each part is the caller's job here —
    /// `RichTextParser` only ever sees a `RichText`. Returns whether anything landed — a page
    /// whose parts all render to nothing inserts no turn, and the caller must not report a
    /// prepend the view will never see.
    func prepend(_ messages: [Message]) -> Bool {
        // reverse to chronological (oldest → newest).
        var older: [Identified<ConversationSnapshot.Turn>] = []
        for message in messages.reversed() {
            if message.role == .user {
                let contents = message.parts.compactMap(Self.user)
                guard !contents.isEmpty else { continue }
                older.append(Identified(model: .user(contents)))
            } else if message.role == .system {
                let responses = message.parts.compactMap { self.incoming($0) }
                guard !responses.isEmpty else { continue }
                older.append(Identified(model: .system(responses)))
            } else {
                let responses = message.parts.compactMap { self.incoming($0) }
                guard !responses.isEmpty else { continue }
                older.append(Identified(model: .bot(responses)))
            }
        }

        // Once history is exhausted this is the true start — pin the synthetic greeting above it.
        if self.showsWelcome, let welcome = self.welcomeMessage {
            older.insert(Identified(model: .bot([.text(AttributedString(welcome))])), at: 0)
        }

        guard !older.isEmpty else { return false }
        self.turns.insert(contentsOf: older, at: 0)
        return true
    }

    /// Builds the optimistic user-turn echo for a send.
    static func echo(text: String, attachments: [OutgoingAttachment]) -> [UserContent] {
        var contents: [UserContent] = []
        if !text.isEmpty {
            contents.append(.text(AttributedString(text)))
        }
        for attachment in attachments {
            guard let url = attachment.dataURL else { continue }
            switch attachment.kind {
            case .image:
                contents.append(.image(MessageImage(
                    url: url,
                    mimeType: attachment.mime,
                    caption: attachment.filename
                )))
            case .file:
                contents.append(.file(MessageFile(
                    filename: attachment.filename ?? "file",
                    url: url,
                    mimeType: attachment.mime
                )))
            }
        }
        return contents
    }

    static func user(_ part: Part) -> UserContent? {
        switch part {
        case .richText(let richText):
            RichTextParser.attributedText(richText).map(UserContent.text)
        case .image(let image):
            .image(image)
        case .file(let file):
            .file(file)
        default:
            nil
        }
    }

    /// Wire part → display model, or `nil` for parts that render nothing (unknown, empty lists,
    /// an upload marker the host does not accept). A message whose parts all map to `nil`
    /// produces no turn at all.
    func incoming(_ part: Part) -> ChatResponse? {
        switch part {
        case .richText(let richText):
            RichTextParser.attributedText(richText).map(ChatResponse.text)
        case .products(let products):
            products.products.isEmpty ? nil : .products(products.products)
        case .suggestions(let suggestions):
            suggestions.suggestions.isEmpty ? nil : .suggestions(suggestions.suggestions)
        case .quickReplies(let quickReplies):
            quickReplies.replies.isEmpty ? nil : .quickReplies(quickReplies.replies)
        case .image(let image):
                .image(image)
        case .file(let file):
                .file(file)
        case .requestImageUpload(let marker):
            self.acceptsImageUploadPrompts ? .requestImageUpload(marker) : nil
        case .requestHumanAgent(let marker):
            self.acceptsHumanAgentPrompts ? .requestHumanAgent(marker) : nil
        case .showContactForm(let marker):
            .form(.contact(marker))
        case .showSupportTicket(let marker):
            .form(.supportTicket(marker))
        case .showForm(let marker):
            .form(.custom(marker))
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

        case .suggestions:
            let cards = deltas.compactMap { delta -> Suggestions.Card? in
                guard case .suggestions(.appendSuggestion(let card)) = delta else { return nil }
                return card
            }

            return cards.isEmpty ? nil : .suggestions(cards)

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
