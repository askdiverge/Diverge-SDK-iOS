//
//  ChatProvider+Turns.swift
//  AIConversation
//

import Foundation

/// In-place mutations of the turn list while a reply streams or fails.
extension ChatProvider {

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

    /// Removes the in-flight turn when the stream ended without ever overwriting its
    /// thinking placeholder — nothing arrived that the visitor could read.
    func dropUnfilledPlaceholder(turnID: UUID) {
        if let index = self.turns.lastIndex(where: { $0.id == turnID }),
           case .bot(let responses) = self.turns[index].model,
           case .placeholder? = responses.first {
            self.turns.remove(at: index)
        }
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

    /// Drops the send-arm id when that optimistic echo is gone (failed send).
    private func clearSentEcho(_ echoID: UUID) {
        if self.lastSentUserTurnID == echoID {
            self.lastSentUserTurnID = nil
        }
    }
}
