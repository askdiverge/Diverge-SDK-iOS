//
//  Part.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-02.
//

/// An ordered part of a message, discriminated on `type`.
///
/// Supports `rich_text`, `table`, and `products`. All other variants
/// decode to `.unknown` and are skipped
/// at render time.
/// [API ref](https://docs.dialoge.ai/api#model/message-part)
package enum Part: Decodable, Sendable, Equatable {

    case richText(RichText)
    case table(Table)
    case products(Products)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type
    }

    private enum PartType: String, Decodable {
        case richText = "rich_text"
        case table
        case products
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container.decode(PartType.self, forKey: .type) {
        case .richText: .richText(try RichText(from: decoder))
        case .table: .table(try Table(from: decoder))
        case .products: .products(try Products(from: decoder))
        case .none: .unknown
        }
    }
}
