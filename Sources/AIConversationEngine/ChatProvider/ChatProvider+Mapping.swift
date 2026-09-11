//
//  ChatProvider+Mapping.swift
//  AIConversation
//

import Foundation

/// Wire part → display model. Pure except for `incoming`, which reads the upload-prompt gate.
extension ChatProvider {

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
