//
//  Part.swift
//  AIConversationEngine
//
//  Created by Daniel Wennberg on 2026-06-02.
//

/// An ordered part of a message, discriminated on `type`.
///
/// Supports `rich_text`, `table`, `products`, `image`, `file`, `request_image_upload`,
/// `request_human_agent`, and the contact / support / custom form markers. All other variants
/// decode to `.unknown` and are skipped at render time. A malformed part of any type also falls
/// back to `.unknown`, so a bad part cannot abort its siblings, its message or the live stream.
/// [API ref](https://docs.askdiverge.ai/api#model/messagepart)
package enum Part: Decodable, Sendable, Equatable {

    case richText(RichText)
    case table(Table)
    case products(Products)
    case image(MessageImage)
    case file(MessageFile)
    case requestImageUpload(RequestImageUpload)
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
        case image
        case file
        case requestImageUpload = "request_image_upload"
        case requestHumanAgent = "request_human_agent"
        case showContactForm = "show_contact_form"
        case showSupportTicket = "show_support_ticket"
        case showForm = "show_form"
    }

    package init(from decoder: any Decoder) throws {
        // A part that doesn't decode, from an unreadable or new `type` to a missing field, is
        // `.unknown`, which rendering skips; a throw would fail its whole message, and with it a
        // page of history or the live stream.
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container?.decode(PartType.self, forKey: .type) {
        case .richText:
            (try? RichText(from: decoder)).map(Part.richText) ?? .unknown
        case .table:
            (try? Table(from: decoder)).map(Part.table) ?? .unknown
        case .products:
            (try? Products(from: decoder)).map(Part.products) ?? .unknown
        case .image:
            (try? MessageImage(from: decoder)).map(Part.image) ?? .unknown
        case .file:
            (try? MessageFile(from: decoder)).map(Part.file) ?? .unknown
        case .requestImageUpload:
            (try? RequestImageUpload(from: decoder)).map(Part.requestImageUpload) ?? .unknown
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
