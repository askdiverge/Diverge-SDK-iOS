//
//  Part.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-02.
//

/// An ordered part of a message, discriminated on `type`.
///
/// Supports `rich_text`, `table`, `products`, `suggestions`, `quick_replies`, `image`, `file`,
/// and `request_image_upload`. Form / livechat markers and all other variants decode to
/// `.unknown` and are skipped at render time. Malformed `image` / `file` / marker payloads
/// also fall back to `.unknown` so a bad attachment cannot abort sibling parts.
/// [API ref](https://docs.dialoge.ai/api#model/message-part)
package enum Part: Decodable, Sendable, Equatable {

    case richText(RichText)
    case table(Table)
    case products(Products)
    case suggestions(Suggestions)
    case quickReplies(QuickReplies)
    case image(MessageImage)
    case file(MessageFile)
    case requestImageUpload(RequestImageUpload)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum PartType: String, Decodable {
        case richText = "rich_text"
        case table
        case products
        case suggestions
        case quickReplies = "quick_replies"
        case image
        case file
        case requestImageUpload = "request_image_upload"
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container.decode(PartType.self, forKey: .type) {
        case .richText: .richText(try RichText(from: decoder))
        case .table: .table(try Table(from: decoder))
        case .products: (try? Products(from: decoder)).map(Part.products) ?? .unknown
        case .suggestions: .suggestions(try Suggestions(from: decoder))
        case .quickReplies:
            if let quickReplies = try? QuickReplies(from: decoder), !quickReplies.replies.isEmpty {
                .quickReplies(quickReplies)
            } else {
                .unknown
            }
        case .image: (try? MessageImage(from: decoder)).map(Part.image) ?? .unknown
        case .file: (try? MessageFile(from: decoder)).map(Part.file) ?? .unknown
        case .requestImageUpload:
            (try? RequestImageUpload(from: decoder)).map(Part.requestImageUpload) ?? .unknown
        case .none: .unknown
        }
    }
}
