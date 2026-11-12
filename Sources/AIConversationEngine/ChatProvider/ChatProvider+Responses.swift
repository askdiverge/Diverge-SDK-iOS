//
//  ChatProvider+Responses.swift
//  AIConversationEngine
//

import Foundation

extension ChatProvider {

    static func user(_ part: Part) -> UserContent? {
        switch part {
        case .richText(let richText):
            RichTextParser.attributedText(richText).map(UserContent.text)
        case .image(let image):
            .image(image)
        default:
            nil
        }
    }

    /// Maps a wire part for an incoming turn. System-role text becomes a centred note, and an
    /// agent's text carries `agent`, the identity its message names; every other non-user role
    /// keeps the usual assistant / agent cards.
    func incoming(_ part: Part, role: Message.Role = .assistant, agent: LivechatAgent? = nil) -> ChatResponse? {
        if role == .system {
            guard case .richText(let richText) = part else { return nil }
            return RichTextParser.attributedText(richText).map(ChatResponse.systemNote)
        }
        switch part {
        case .richText(let richText):
            guard let text = RichTextParser.attributedText(richText) else { return nil }
            return role == .agent ? .agentText(text, agent: agent) : .text(text)
        case .products(let products):
            return .products(products.products)
        case .table(let table):
            return .table(
                TableMapper.content(
                    caption: table.caption,
                    headers: table.headers,
                    alignments: table.alignments,
                    rows: table.rows
                )
            )
        case .showContactForm(let marker):
            return .form(.contact(marker))
        case .showSupportTicket(let marker):
            return ConversationForm.supportTicket(marker).map(ChatResponse.form)
        case .showForm(let marker):
            return .form(.custom(marker))
        case .image(let image):
            return .image(image)
        case .file(let file):
            return .file(file)
        case .requestImageUpload(let marker):
            return self.acceptsImageUploadPrompts ? .requestImageUpload(marker) : nil
        case .requestHumanAgent(let marker):
            return .requestHumanAgent(marker)
        case .unknown:
            return nil
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
