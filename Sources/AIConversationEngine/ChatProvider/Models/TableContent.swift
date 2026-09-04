//
//  TableContent.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-16.
//

import Foundation

/// Display model for a table. Each `Column` folds a header with its alignment, so a
/// cell's alignment is just `columns[col].alignment` at render time.
///
/// A column grid can only draw when it's symmetric, so the initialiser rectangularizes
/// `rows` to `columns.count`. WYSIWYG holds for valid data, but can't extend to a shape
/// that won't draw or would trap.
/// Overflow cells are dropped (they belong to no column,
/// and we don't fabricate one), and short rows are padded with blanks (a normal empty cell in a table).
package struct TableContent: Sendable, Equatable {

    package let caption: String?
    package let columns: [Column]
    package let rows: [[Cell]]

    /// Pads short rows with empty cells and drops overflow, guaranteeing every row holds
    /// exactly `columns.count` cells.
    package init(caption: String?, columns: [Column], rows: [[Cell]]) {
        self.caption = caption
        self.columns = columns
        self.rows = rows.map { row in
            let cells = Array(row.prefix(columns.count))
            return cells + Array(repeating: Cell(elements: []), count: columns.count - cells.count)
        }
    }

    package struct Column: Sendable, Equatable {
        package let header: Cell
        package let alignment: Alignment
    }

    package enum Alignment: Sendable, Equatable {
        case leading, center, trailing
    }

    package struct Cell: Sendable, Equatable {
        package let elements: [Element]

        package enum Element: Sendable, Equatable {
            case text(AttributedString)
            case image(Table.Image)
        }
    }
}
