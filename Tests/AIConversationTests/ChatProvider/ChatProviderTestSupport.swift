//
//  ChatProviderTestSupport.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

// MARK: - Snapshot accessors

extension ConversationSnapshot {
    /// User-turn contents in chronological order — content-only assertions.
    var userTurns: [[UserContent]] {
        self.turns.compactMap {
            if case .user(let contents) = $0.model { return contents }
            return nil
        }
    }

    /// Bot-turn responses in chronological order — content-only assertions.
    var botTurns: [[ChatResponse]] {
        self.turns.compactMap {
            if case .bot(let responses) = $0.model { return responses }
            return nil
        }
    }
}

// MARK: - Fixtures

/// Shared fixtures for the `ChatProvider` suites — conform a suite to pick them up.
protocol ChatProviderTestHelpers {}

extension ChatProviderTestHelpers {

    /// Short label for a turn's first text bubble — used by ordering assertions.
    static func label(_ turn: ConversationSnapshot.Turn) -> String {
        switch turn {
        case .bot(let responses), .system(let responses):
            if case .text(let text)? = responses.first { return String(text.characters) }
        case .user(let contents):
            if case .text(let text)? = contents.first { return String(text.characters) }
        }
        return "?"
    }

    /// The rich_text delta sequence that streams a single paragraph of `text`.
    func textDeltas(_ text: String, partId: String = "p") -> [StreamEvent] {
        [
            .delta(partId: partId, .richText(.start)),
            .delta(partId: partId, .richText(.startBlock(index: 0, type: .paragraph))),
            .delta(partId: partId, .richText(.appendText(index: 0, text: text)))
        ]
    }

    /// The authoritative `part` for a single paragraph of `text`.
    func textPart(_ text: String, partId: String = "p") -> StreamEvent {
        .part(.richText(RichText(partId: partId, blocks: [.paragraph(.init(spans: [.text(text)]))])))
    }

    /// An assistant history message carrying a single paragraph of `text`.
    func assistantMessage(_ text: String) -> Message {
        Message(
            messageId: "m",
            role: .assistant,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }

    /// A user history message carrying a single paragraph of `text`.
    func userMessage(_ text: String) -> Message {
        Message(
            messageId: "u",
            role: .user,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }

    /// A system history message carrying a single paragraph of `text` — folds into a bot turn.
    func systemMessage(_ text: String) -> Message {
        Message(
            messageId: "sys",
            role: .system,
            parts: [.richText(RichText(partId: "", blocks: [.paragraph(.init(spans: [.text(text)]))]))],
            createdAt: "2026-01-01T00:00:00.000Z"
        )
    }

    /// An assistant history message whose only part is one this client cannot render.
    func unknownPartMessage() -> Message {
        Message(messageId: "x", role: .assistant, parts: [.unknown], createdAt: "2026-01-01T00:00:00.000Z")
    }

    /// Drains snapshots until the newest turn's first bubble reads `text` — the point at which the
    /// provider has consumed every event published so far and is suspended on the next one.
    func awaitPreview(_ text: String, from snapshots: inout AsyncStream<ConversationSnapshot>.Iterator) async {
        while let snapshot = await snapshots.next() {
            if snapshot.turns.last.map({ Self.label($0.model) }) == text { return }
        }
        Issue.record("stream ended before the preview \"\(text)\" was published")
    }

    /// A suggestion card fixture.
    func suggestionCard(
        id: String,
        title: String,
        prompt: String,
        description: String? = nil
    ) -> Suggestions.Card {
        Suggestions.Card(
            id: id,
            title: title,
            description: description,
            imageUrl: URL(string: "https://cdn.example.com/\(id).jpg")!,
            promptText: prompt
        )
    }

    /// The suggestions delta sequence that streams the given cards.
    func suggestionDeltas(_ cards: [Suggestions.Card], partId: String = "sug") -> [StreamEvent] {
        [.delta(partId: partId, .suggestions(.start))]
            + cards.map { .delta(partId: partId, .suggestions(.appendSuggestion($0))) }
            + [.delta(partId: partId, .endPart)]
    }

    /// The authoritative `part` for a suggestions collection.
    func suggestionsPart(_ cards: [Suggestions.Card], partId: String = "sug") -> StreamEvent {
        .part(.suggestions(Suggestions(partId: partId, suggestions: cards)))
    }

    /// A request_image_upload marker fixture — contract defaults unless overridden.
    func requestImageUpload(
        partId: String = "part_upload_1",
        acceptedTypes: [String] = RequestImageUpload.defaultAcceptedTypes,
        maxSizeBytes: Int = RequestImageUpload.defaultMaxSizeBytes
    ) -> RequestImageUpload {
        RequestImageUpload(partId: partId, acceptedTypes: acceptedTypes, maxSizeBytes: maxSizeBytes)
    }

    /// The authoritative `part` for a request_image_upload marker.
    func requestImageUploadPart(_ marker: RequestImageUpload) -> StreamEvent {
        .part(.requestImageUpload(marker))
    }

    /// An assistant-sent image fixture.
    func messageImage(
        url: String = "https://cdn.example.com/uploads/receipt.jpg",
        caption: String? = "Receipt"
    ) -> MessageImage {
        MessageImage(
            url: URL(string: url)!,
            thumbnailUrl: URL(string: "https://cdn.example.com/uploads/receipt_thumb.jpg"),
            caption: caption
        )
    }

    /// An assistant-sent file fixture.
    func messageFile(
        filename: String = "invoice.pdf",
        url: String = "https://cdn.example.com/invoice.pdf"
    ) -> MessageFile {
        MessageFile(
            filename: filename,
            url: URL(string: url)!,
            mimeType: "application/pdf",
            sizeBytes: 48231
        )
    }

    /// The terminal `done` event carrying the given parts.
    func doneMessage(parts: [Part]) -> StreamEvent {
        .done(
            Message(
                messageId: "done",
                role: .assistant,
                parts: parts,
                createdAt: "2026-01-01T00:00:00.000Z"
            ),
            visitorToken: nil
        )
    }
}

struct TestError: Error {}
