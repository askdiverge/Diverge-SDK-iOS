//
//  ChatProvider+Panes.swift
//  AIConversationEngine
//

import Foundation

extension ChatProvider {

    /// Adds a visitor turn, or a bubble on the newest one when a new turn would break the pairing.
    func appendUser(_ bubbles: [UserContent]) {
        if self.user.isEmpty, self.incoming.isEmpty {
            self.botLeads = false
        }
        if Self.startsTurn(count: self.user.count, otherCount: self.incoming.count, leads: !self.botLeads) {
            self.user.append(Identified(model: bubbles))
        } else {
            let last = self.user[self.user.count - 1]
            self.user[self.user.count - 1] = Identified(id: last.id, model: last.model + bubbles)
        }
    }

    /// Adds a bot turn, or a bubble on the newest one when a new turn would break the pairing.
    func appendIncoming(_ responses: [ChatResponse]) {
        if self.user.isEmpty, self.incoming.isEmpty {
            self.botLeads = true
        }
        if Self.startsTurn(count: self.incoming.count, otherCount: self.user.count, leads: self.botLeads) {
            self.incoming.append(Identified(model: responses))
        } else {
            let last = self.incoming[self.incoming.count - 1]
            self.incoming[self.incoming.count - 1] = Identified(id: last.id, model: last.model + responses)
        }
    }

    /// Whether new content starts a turn in a pane of `count` turns. Turns pair up by index across
    /// the panes, leading pane first, so the leading pane may start a turn only when the panes are
    /// level, and the other only to catch up. A pane that runs two turns ahead loses one from
    /// ``ConversationSnapshot/turns``.
    static func startsTurn(count: Int, otherCount: Int, leads: Bool) -> Bool {
        leads ? count == otherCount : count < otherCount
    }

    /// Removes the newest `count` visitor bubbles (and their turn when empty), returning text
    /// for input restore. An unanswered prior bubble on the same turn is left in place.
    @discardableResult
    func popLastUserBubbles(count: Int) -> String {
        guard count > 0, let last = self.user.popLast() else { return "" }
        var bubbles = last.model
        let removeCount = min(count, bubbles.count)
        let removed = Array(bubbles.suffix(removeCount))
        bubbles.removeLast(removeCount)
        if !bubbles.isEmpty {
            self.user.append(Identified(id: last.id, model: bubbles))
        }
        return removed.compactMap { content -> String? in
            if case .text(let text) = content { return String(text.characters) }
            return nil
        }.joined(separator: "\n")
    }

    /// Buckets a history page into the two panes and prepends it (older turns go
    /// above existing ones). Messages in a row from the same side form one turn, and their
    /// parts the turn's adjacent bubbles; the page's newest turn joins the existing first turn
    /// when both are the same side, so the panes stay paired. Selecting the parser for each part
    /// is the caller's job here — `RichTextParser` only ever sees a `RichText`.
    func prepend(_ messages: [Message]) {
        self.livechatMessageIDs.formUnion(messages.map(\.messageId))

        // Chronological (oldest → newest), one entry per run of messages from one side.
        var runs: [ConversationSnapshot.Turn] = []
        for message in messages.reversed() {
            switch (message.role, runs.last) {
            case (.user, .user(let bubbles)):
                runs[runs.count - 1] = .user(bubbles + message.parts.compactMap(Self.user))
            case (.user, _):
                runs.append(.user(message.parts.compactMap(Self.user)))
            case (_, .bot(let responses)):
                runs[runs.count - 1] = .bot(responses + message.parts.compactMap { self.incoming($0, role: message.role) })
            default:
                runs.append(.bot(message.parts.compactMap { self.incoming($0, role: message.role) }))
            }
        }

        if !self.user.isEmpty || !self.incoming.isEmpty {
            switch (runs.last, self.botLeads) {
            case (.user(let bubbles), false):
                self.user[0] = Identified(id: self.user[0].id, model: bubbles + self.user[0].model)
                runs.removeLast()
            case (.bot(let responses), true):
                self.incoming[0] = Identified(id: self.incoming[0].id, model: responses + self.incoming[0].model)
                runs.removeLast()
            default:
                break
            }
        }
        guard let first = runs.first else { return }

        var olderUser: [Identified<[UserContent]>] = []
        var olderIncoming: [Identified<[ChatResponse]>] = []
        for run in runs {
            switch run {
            case .user(let bubbles): olderUser.append(Identified(model: bubbles))
            case .bot(let responses): olderIncoming.append(Identified(model: responses))
            }
        }
        self.user.insert(contentsOf: olderUser, at: 0)
        self.incoming.insert(contentsOf: olderIncoming, at: 0)
        if case .bot = first {
            self.botLeads = true
        } else {
            self.botLeads = false
        }
    }
}
