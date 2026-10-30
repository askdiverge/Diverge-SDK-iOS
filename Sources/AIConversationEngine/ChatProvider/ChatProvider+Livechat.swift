//
//  ChatProvider+Livechat.swift
//  AIConversationEngine
//

import Foundation
import AIConversationCore

extension ChatProvider {

    /// Folds messages from the livechat poller into the panes, skipping ids already shown.
    package func appendLivechat(_ messages: [LivechatMessage]) {
        guard !self.isBusy else {
            self.deferredLivechat.append(.messages(messages))
            return
        }
        self.ingestLivechat(messages)
    }

    /// Appends a session-local boundary note after the newest bot content, keeping the panes
    /// paired. During a send, reset or delete it waits, in order with the livechat messages,
    /// until the operation finishes.
    package func note(_ note: LivechatNote) {
        guard !self.isBusy else {
            self.deferredLivechat.append(.note(note))
            return
        }
        self.appendIncoming([.livechatNote(note)])
        self.publish()
    }

    /// Sends the visitor's text and/or attachments to the agent while a livechat session is
    /// active. The echo shows at once, and the stored message's id is recorded so the poller's
    /// copy isn't shown again. A send with neither does nothing.
    package func sendLivechat(
        _ text: String,
        attachments: [OutgoingAttachment]
    ) async throws(SendFailure) {
        // The API takes a message of at least one part.
        guard !text.isEmpty || !attachments.isEmpty else { return }
        try self.beginOperation()
        defer { self.finishOperation() }

        let page = await self.pageContext()
        let echo = Self.echo(text: text, attachments: attachments)
        self.appendUser(echo)
        self.publish()

        do {
            let stored = try await self.postLivechat(text, attachments: attachments, page: page)
            self.livechatMessageIDs.insert(stored.messageId)
        } catch ChatServiceError.sessionExpired {
            self.endConversation()
            throw SendFailure.sessionExpired
        } catch ChatServiceError.conflict {
            self.popLastUserBubbles(count: echo.count)
            self.publish()
            throw .livechatInactive(popped: .init(text: text, attachments: attachments))
        } catch {
            self.popLastUserBubbles(count: echo.count)
            self.publish()
            throw .retry(popped: .init(text: text, attachments: attachments), body: nil)
        }
    }

    /// Clears the conversation after a call outside the provider — the livechat poller, a form
    /// submit — saw the session end (401). During a send, reset or delete the clear waits until
    /// the operation finishes.
    package func expireSession() {
        guard !self.isBusy else {
            self.expiresAfterOperation = true
            return
        }
        self.endConversation()
    }

    func ingestLivechat(_ messages: [LivechatMessage]) {
        var changed = false
        for message in messages {
            if let head = self.historyHead, let createdAt = Self.milliseconds(of: message.createdAt), createdAt <= head {
                continue
            }
            guard self.livechatMessageIDs.insert(message.messageId).inserted else { continue }
            if message.role == .user {
                let bubbles = message.parts.compactMap(Self.user)
                guard !bubbles.isEmpty else { continue }
                self.appendUser(bubbles)
            } else {
                let responses = message.parts.compactMap { self.incoming($0, role: message.role) }
                guard !responses.isEmpty else { continue }
                self.appendIncoming(responses)
            }
            changed = true
        }
        if changed { self.publish() }
    }

    /// Milliseconds since 1970 of an RFC 3339 `created_at`, whatever its fraction digits and
    /// offset; `nil` when it doesn't parse. History keeps a message's stored timestamp as written,
    /// often with microseconds, while the livechat log writes milliseconds in UTC.
    static func milliseconds(of timestamp: String) -> Int64? {
        var whole = timestamp
        var millis: Int64 = 0
        if let dot = timestamp.firstIndex(of: ".") {
            let rest = timestamp[timestamp.index(after: dot)...]
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            millis = Int64(String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
            whole = String(timestamp[..<dot]) + rest.dropFirst(digits.count)
        }
        // A timestamp that doesn't parse has no place in the order, which is what `nil` says.
        guard let date = try? Date(whole, strategy: .iso8601) else { return nil }
        return Int64(date.timeIntervalSince1970) * 1000 + millis
    }

    /// Posts a livechat message under one operation id, and once more when the first attempt may
    /// have been stored: the server answers a repeated id with the stored copy, so a send whose
    /// response was lost is never stored twice.
    func postLivechat(
        _ text: String,
        attachments: [OutgoingAttachment],
        page: String?
    ) async throws(ChatServiceError) -> LivechatMessage {
        let operationId = UUID().uuidString
        do {
            return try await self.service.sendLivechatMessage(
                text,
                attachments: attachments,
                page: page,
                operationId: operationId
            )
        } catch let error where Self.mayHaveBeenStored(error) {
            return try await self.service.sendLivechatMessage(
                text,
                attachments: attachments,
                page: page,
                operationId: operationId
            )
        }
    }

    /// Whether a failed livechat send may still have been stored: the connection dropped or timed
    /// out after the request went out, or the response couldn't be read.
    static func mayHaveBeenStored(_ error: ChatServiceError) -> Bool {
        switch error {
        case .transport(.connection(let error)):
            [.timedOut, .networkConnectionLost, .badServerResponse, .cannotParseResponse].contains(error.code)
        case .transport(.decoding):
            true
        default:
            false
        }
    }
}

/// A livechat delivery held back while an operation is in flight.
enum DeferredLivechat {
    case messages([LivechatMessage])
    case note(LivechatNote)
}
