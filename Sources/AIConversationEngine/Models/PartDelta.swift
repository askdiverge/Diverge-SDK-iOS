//
//  PartDelta.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-05-26.
//

import Foundation

/// An incremental streamed update to an in-progress part, grouped by the part type
/// it builds. Each type has its own grammar:
/// ```
/// rich_text: .richText(.start) → (.startBlock → (.appendText|.appendSpan|.appendItem)* → .endBlock)* → .endPart
/// products: .products(.start) → .products(.appendProduct)* → .endPart
/// table: .table(.start) → .table(.appendRow)* → .endPart
/// ```
/// `endPart` is shared and untyped — the wire `end_part` carries no part type, so the
/// consumer (which knows the open part) finalises on it.
/// [API ref](https://docs.dialoge.ai/api#model/stream-part-delta)
package enum PartDelta: Decodable, Sendable, Equatable {

    case richText(RichTextDelta)
    case products(ProductsDelta)
    case table(TableDelta)

    /// Close the current part. The authoritative `part` event follows.
    case endPart
    /// Unrecognised action, or `start_part` with an unrecognised `part_type`.
    case unknown

    private enum CodingKeys: String, CodingKey {
        case action
        case partType
        case blockIndex
        case blockType
        case text
        case span
        case item
        case product
        case row
    }

    private enum Action: String, Decodable {
        case startPart = "start_part"
        case startBlock = "start_block"
        case appendText = "append_text"
        case appendSpan = "append_span"
        case appendItem = "append_item"
        case appendProduct = "append_product"
        case appendRow = "append_row"
        case endBlock = "end_block"
        case endPart = "end_part"
    }

    /// Wire-level `part_type` discriminator for `start_part`.
    private enum StartPartType: String, Decodable {
        case richText = "rich_text"
        case products
        case table
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = switch try? container.decode(Action.self, forKey: .action) {
        case .startPart:
            // `start_part` opens rich_text/products/table — discriminate on `part_type`.
            switch try? container.decode(StartPartType.self, forKey: .partType) {
            case .richText: .richText(.start)
            case .products: .products(.start)
            case .table: .table(.start(try TableDelta.StartTable(from: decoder)))
            case .none: .unknown
            }

        case .startBlock:
                .richText(
                    .startBlock(
                        index: try container.decode(Int.self, forKey: .blockIndex),
                        type: try container.decode(RichTextDelta.BlockType.self, forKey: .blockType)
                    )
                )
        case .appendText:
                .richText(
                    .appendText(
                        index: try container.decode(Int.self, forKey: .blockIndex),
                        text: try container.decode(String.self, forKey: .text)
                    )
                )
        case .appendSpan:
                .richText(
                    .appendSpan(
                        index: try container.decode(Int.self, forKey: .blockIndex),
                        span: try container.decode(RichText.Span.self, forKey: .span)
                    )
                )
        case .appendItem:
                .richText(
                    .appendItem(
                        index: try container.decode(Int.self, forKey: .blockIndex),
                        item: try container.decode(RichText.BulletList.Item.self, forKey: .item)
                    )
                )
        case .appendProduct:
                .products(
                    .appendProduct(
                        try container.decode(Products.Card.self, forKey: .product)
                    )
                )
        case .appendRow:
                .table(
                    .appendRow(
                        try container.decode([Table.Cell].self, forKey: .row)
                    )
                )
        case .endBlock:
                .richText(
                    .endBlock(
                        index: try container.decode(Int.self, forKey: .blockIndex)
                    )
                )
        case .endPart: .endPart
        case .none: .unknown
        }
    }
}

extension PartDelta {

    /// Build instructions for an in-progress rich_text part.
    package enum RichTextDelta: Sendable, Equatable {
        /// Begin the part (`start_part` + `part_type=rich_text`).
        case start
        /// Open a new block at `index`.
        case startBlock(index: Int, type: BlockType)
        /// Append plain text to the paragraph block at `index`.
        case appendText(index: Int, text: String)
        /// Append a finished structured span to the paragraph block at `index`.
        case appendSpan(index: Int, span: RichText.Span)
        /// Append a finished item to the bullet-list block at `index`.
        case appendItem(index: Int, item: RichText.BulletList.Item)
        /// Close the block at `index`.
        case endBlock(index: Int)

        /// The block type opened by `startBlock`.
        package enum BlockType: String, ExtendableEnum, Sendable {
            case paragraph
            case bulletList = "bullet_list"
            case unknown
        }
    }

    /// Build instructions for an in-progress products part.
    package enum ProductsDelta: Sendable, Equatable {
        /// Begin the part (`start_part` + `part_type=products`).
        case start
        /// Append a finished product card.
        case appendProduct(Products.Card)
    }

    /// Build instructions for an in-progress table part.
    package enum TableDelta: Sendable, Equatable {
        /// Begin the part, carrying headers/alignments/caption up front
        /// (`start_part` + `part_type=table`).
        case start(StartTable)
        /// Append a finished row.
        case appendRow([Table.Cell])

        /// Up-front payload for an in-progress table part.
        /// [API ref](https://docs.dialoge.ai/api#model/stream-start-table-part-delta)
        package struct StartTable: Decodable, Sendable, Equatable {
            package let headers: [Table.Cell]
            package let alignments: [Table.Alignment]?
            package let caption: String?
        }
    }
}
