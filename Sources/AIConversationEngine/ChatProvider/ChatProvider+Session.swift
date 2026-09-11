//
//  ChatProvider+Session.swift
//  AIConversation
//

import Foundation

/// History paging and the session-level operations: reset, delete, GDPR export.
extension ChatProvider {

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

    /// Drops all conversation state and resets pagination — after a successful reset
    /// or delete the next session starts clean (the welcome is re-seeded).
    func clear() {
        self.turns = []
        self.paginator = Paginator()
        self.streamingTurnID = nil
        self.lastSentUserTurnID = nil
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
}
