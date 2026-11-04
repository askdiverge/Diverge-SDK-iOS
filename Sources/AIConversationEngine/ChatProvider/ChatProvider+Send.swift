//
//  ChatProvider+Send.swift
//  AIConversationEngine
//

import Foundation
import AIConversationCore

extension ChatProvider {

    /// Sends a user message (text and/or attachments) and folds the streamed reply into the
    /// conversation. A send with neither does nothing.
    package func send(_ text: String, attachments: [OutgoingAttachment]) async throws(SendFailure) {
        // The API takes a message of at least one part.
        guard !text.isEmpty || !attachments.isEmpty else { return }

        // Single-flight — reject a send while a reply is already streaming.
        try self.beginOperation()
        defer { self.finishOperation() }

        // Mint the in-flight turn and mark it live before the first suspension, so concurrent
        // sends bounce and the view can flag exactly this turn from the snapshot.
        let inFlight = Identified<[ChatResponse]>(model: [.placeholder(AttributedString("• • •"))])
        self.streamingTurnID = inFlight.id

        // Extra context
        let page = await self.pageContext()

        // Optimistic echo — the user turn shows immediately (text + any pending media).
        let echo = Self.echo(text: text, attachments: attachments)
        self.appendUser(echo)
        self.publish()

        // In-flight assistant turn, the thinking placeholder fills the pre-delta gap
        // the first streamed response overwrites index 0. Dropped on failure.
        self.incoming.append(inFlight)

        // Reveal placeholder only if the reply is slow enough to warrant it — a fast
        // reply overwrites index 0 before this fires
        let reveal = Task {
            // Only cancellation throws here, and the guard below handles that.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.publish()
        }

        defer { reveal.cancel() }

        var buffer = DeltaBuffer { Self.response(for: $0) }

        do {
            for try await event in self.service.sendMessage(text, attachments: attachments, page: page) {
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
            self.endConversation()
            throw SendFailure.sessionExpired

        } catch ChatServiceError.stream(let error) {
            let popped = self.discardInFlight(echoCount: echo.count)
            self.publish()
            throw .retry(popped: .init(text: popped, attachments: attachments), body: error.message)

        } catch ChatServiceError.conflict {
            let popped = self.discardInFlight(echoCount: echo.count)
            self.publish()
            throw .livechatActive(popped: .init(text: popped, attachments: attachments))

        } catch {
            let popped = self.discardInFlight(echoCount: echo.count)
            self.publish()
            throw .retry(popped: .init(text: popped, attachments: attachments), body: nil)
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
                let response = self.incoming(part)
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

    /// Discards the unfinished assistant reply and pops the user echo bubbles, returning their
    /// text for the caller to restore to the input.
    func discardInFlight(echoCount: Int) -> String {
        self.streamingTurnID = nil
        self.incoming.removeLast()
        return self.popLastUserBubbles(count: echoCount)
    }
}
