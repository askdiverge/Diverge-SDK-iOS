//
//  Table.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// A structured table part extracted from the assistant response.
/// [API ref](https://docs.dialoge.ai/api#model/table-content)
package struct Table: Decodable, Sendable, Equatable {

    package let partId: String
    package let caption: String?
    package let headers: [Cell]
    package let alignments: [Alignment]?
    package let rows: [[Cell]]
}

extension Table {

    /// Per-column text alignment.
    package enum Alignment: String, ExtendableEnum, Sendable {
        case left
        case center
        case right
        case unknown
    }

    /// Structured content for a single table cell.
    /// [API ref](https://docs.dialoge.ai/api#model/table-cell)
    package struct Cell: Decodable, Sendable, Equatable {

        package let blocks: [Block]

        /// A block inside a table cell, discriminated on `type`.
        /// Cells support the rich-text blocks plus an image block —
        /// a superset of `RichText.Block`.
        /// [API ref](https://docs.dialoge.ai/api#model/table-cell-block)
        package enum Block: Decodable, Sendable, Equatable {

            case paragraph(RichText.Paragraph)
            case bulletList(RichText.BulletList)
            case image(Image)
            case unknown

            private enum CodingKeys: String, CodingKey {
                case type
            }

            private enum BlockType: String, Decodable {
                case paragraph
                case bulletList = "bullet_list"
                case image
            }

            package init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self = switch try? container.decode(BlockType.self, forKey: .type) {
                case .paragraph: .paragraph(try RichText.Paragraph(from: decoder))
                case .bulletList: .bulletList(try RichText.BulletList(from: decoder))
                case .image: .image(try Image(from: decoder))
                case .none: .unknown
                }
            }
        }
    }

    /// An image rendered inside a table cell.
    /// [API ref](https://docs.dialoge.ai/api#model/table-cell-image-block)
    package struct Image: Decodable, Sendable, Equatable {
        package let url: URL
        package let thumbnailUrl: URL?
        package let alt: String?
    }
}
