//
//  DataGrid.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-09.
//

import SwiftUI

/// A fixed-column grid that owns every cell's chrome.
/// Calls the block closures only to populate a cell's content.
/// The caller just supplies blocks, the grid guarantees a solid, stroked cell.
///
/// Columns share the width equally. Row height is the tallest cell in that row (per-row, from each
/// cell's intrinsic height — no forced fill, so no row collapses into uniform). Content top-aligns.
///
/// `columns` is the contract: every row draws exactly that many slots, a short row pads its tail,  a long row drops its overflow.
struct DataGrid<Item, Header: View, Cell: View>: View {

    struct Style {
        var padding: CGFloat = 0
        var headerBackground: Color
        var rowBackground: Color
        var stroke: Color?
    }

    let columns: Int
    let alignments: [HorizontalAlignment]
    let header: [Item]?
    let rows: [[Item]]
    let style: Style

    @ViewBuilder let headerCell: (Item) -> Header
    @ViewBuilder let bodyCell: (Item) -> Cell

    private let lineWidth: CGFloat = 1

    var body: some View {
        // 1. Spacing dictates the thickness of the inner grid lines
        Grid(horizontalSpacing: lineWidth, verticalSpacing: lineWidth) {
            if let header = self.header {
                GridRow {
                    ForEach(0 ..< self.columns, id: \.self) { column in
                        self.cell(background: self.style.headerBackground, column: column) {
                            if header.indices.contains(column) {
                                self.headerCell(header[column])
                            }
                        }
                    }
                }
            }

            ForEach(Array(self.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(0 ..< self.columns, id: \.self) { column in
                        self.cell(background: self.style.rowBackground, column: column) {
                            if row.indices.contains(column) {
                                self.bodyCell(row[column])
                            }
                        }
                    }
                }
            }
        }
        .background(self.style.stroke ?? .clear)
        .border(self.style.stroke ?? .clear, width: self.lineWidth)
    }

    private func cell<Content: View>(
        background: Color,
        column: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let alignment = self.alignment(column)

        return VStack(alignment: alignment, spacing: 0) {
            content()
        }
        .padding(self.style.padding)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: Alignment(horizontal: alignment, vertical: .top)
        )
        .background(background)
        .gridCellUnsizedAxes(.vertical)
    }

    private func alignment(_ column: Int) -> HorizontalAlignment {
        self.alignments.indices.contains(column) ? self.alignments[column] : .leading
    }
}
