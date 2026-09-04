//
//  TableMapper.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// Maps the table wire model or its streamed components to `TableContent`. Header and
/// per-column alignment fold into `Column`
/// rows are rectangularized to the column count.
/// Cell text blocks run through the shared `RichTextParser`.
enum TableMapper {

    static func content(
        caption: String?,
        headers: [Table.Cell],
        alignments: [Table.Alignment]?,
        rows: [[Table.Cell]]
    ) -> TableContent {
        let columns = headers.enumerated().map { index, header in
            TableContent.Column(
                header: self.cell(header),
                alignment: self.alignment(
                    alignments.flatMap { index < $0.count ? $0[index] : nil }
                )
            )
        }

        return TableContent(
            caption: caption,
            columns: columns,
            rows: rows.map { $0.map(self.cell) }
        )
    }

    private static func cell(_ cell: Table.Cell) -> TableContent.Cell {
        TableContent.Cell(elements: cell.blocks.compactMap(self.element))
    }

    private static func element(block: Table.Cell.Block) -> TableContent.Cell.Element? {
        switch block {
        case .paragraph(let paragraph):
            RichTextParser.attributedText(
                RichText(
                    partId: "",
                    blocks: [.paragraph(paragraph)]
                )
            )
            .map(TableContent.Cell.Element.text)

        case .bulletList(let list):
            RichTextParser.attributedText(
                RichText(
                    partId: "",
                    blocks: [.bulletList(list)]
                )
            )
            .map(TableContent.Cell.Element.text)

        case .image(let image): .image(image)
        case .unknown: nil
        }
    }

    private static func alignment(_ alignment: Table.Alignment?) -> TableContent.Alignment {
        switch alignment {
        case .center: .center
        case .right: .trailing
        case .left, .unknown, .none: .leading
        }
    }
}
