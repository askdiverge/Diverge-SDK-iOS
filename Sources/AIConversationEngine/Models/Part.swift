//
//  Part.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-02.
//

/// An ordered part of a message, discriminated on `type`.
///
/// Supports `rich_text`, `table`, `products`, `file`, `request_human_agent`, and the
/// contact / support / custom form markers. All other variants decode to `.unknown` and are
/// skipped at render time. Malformed marker payloads also fall back to `.unknown` so a bad
/// part cannot abort sibling parts.
/// [API ref](https://docs.askdiverge.ai/api#model/messagepart)
package enum Part: Decodable, Sendable, Equatable {

    case richText(RichText)
    case table(Table)
    case products(Products)
    case file(MessageFile)
    case requestHumanAgent(RequestHumanAgent)
    case showContactForm(ShowContactForm)
    case showSupportTicket(ShowSupportTicket)
    case showForm(ShowForm)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum PartType: String, Decodable {
        case richText = "rich_text"
        case table
        case products
        case file
        case requestHumanAgent = "request_human_agent"
        case showContactForm = "show_contact_form"
        case showSupportTicket = "show_support_ticket"
        case showForm = "show_form"
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container.decode(PartType.self, forKey: .type) {
        case .richText: .richText(try RichText(from: decoder))
        case .table: .table(try Table(from: decoder))
        case .products: .products(try Products(from: decoder))
        case .file:
            (try? MessageFile(from: decoder)).map(Part.file) ?? .unknown
        case .requestHumanAgent:
            (try? RequestHumanAgent(from: decoder)).map(Part.requestHumanAgent) ?? .unknown
        case .showContactForm:
            (try? ShowContactForm(from: decoder)).map(Part.showContactForm) ?? .unknown
        case .showSupportTicket:
            (try? ShowSupportTicket(from: decoder)).map(Part.showSupportTicket) ?? .unknown
        case .showForm:
            (try? ShowForm(from: decoder)).map(Part.showForm) ?? .unknown
        case .none: .unknown
        }
    }
}
