//
//  TableMapperTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("TableMapper — table wire → TableContent")
struct TableMapperTests {

    // MARK: - Columns & alignment

    @Test("headers fold into columns with the caption")
    func headersFoldIntoColumns() {
        let table = TableMapper.content(caption: "cap", headers: [self.cell("A"), self.cell("B")], alignments: nil, rows: [])
        #expect(table.caption == "cap")
        #expect(table.columns.count == 2)
        #expect(table.columns[0].header == TableContent.Cell(elements: [.text(AttributedString("A"))]))
    }

    @Test("alignments zip per column: left→leading, center, right→trailing")
    func alignmentsMap() {
        let table = TableMapper.content(
            caption: nil,
            headers: [self.cell("a"), self.cell("b"), self.cell("c")],
            alignments: [.left, .center, .right],
            rows: []
        )
        #expect(table.columns.map(\.alignment) == [.leading, .center, .trailing])
    }

    @Test("short or absent alignments default to leading")
    func alignmentDefaults() {
        let short = TableMapper.content(caption: nil, headers: [self.cell("a"), self.cell("b")], alignments: [.right], rows: [])
        #expect(short.columns.map(\.alignment) == [.trailing, .leading])

        let absent = TableMapper.content(caption: nil, headers: [self.cell("a")], alignments: nil, rows: [])
        #expect(absent.columns.map(\.alignment) == [.leading])
    }

    @Test("unknown alignment defaults to leading")
    func unknownAlignment() {
        let table = TableMapper.content(caption: nil, headers: [self.cell("a")], alignments: [.unknown], rows: [])
        #expect(table.columns.map(\.alignment) == [.leading])
    }

    // MARK: - Rectangularization

    @Test("short rows pad with empty cells")
    func shortRowsPad() {
        let table = TableMapper.content(
            caption: nil,
            headers: [self.cell("a"), self.cell("b"), self.cell("c")],
            alignments: nil,
            rows: [[self.cell("1")]]
        )
        #expect(table.rows[0].count == 3)
        #expect(table.rows[0][1] == TableContent.Cell(elements: []))
        #expect(table.rows[0][2] == TableContent.Cell(elements: []))
    }

    @Test("overflow cells are dropped")
    func overflowDropped() {
        let table = TableMapper.content(
            caption: nil,
            headers: [self.cell("a")],
            alignments: nil,
            rows: [[self.cell("1"), self.cell("2"), self.cell("3")]]
        )
        #expect(table.rows[0].count == 1)
        #expect(table.rows[0][0] == TableContent.Cell(elements: [.text(AttributedString("1"))]))
    }

    // MARK: - Cells

    @Test("image block maps to an image element, reusing the wire image as-is")
    func imageCell() {
        let image = Table.Image(
            url: URL(string: "https://img/x.jpg")!,
            thumbnailUrl: URL(string: "https://img/t.jpg")!,
            alt: "alt"
        )
        let table = TableMapper.content(
            caption: nil,
            headers: [self.cell("h")],
            alignments: nil,
            rows: [[Table.Cell(blocks: [.image(image)])]]
        )
        #expect(table.rows[0][0].elements == [.image(image)])
    }

    @Test("text then image preserves block order")
    func interleavedCell() {
        let image = Table.Image(url: URL(string: "https://img/x.jpg")!, thumbnailUrl: nil, alt: nil)
        let mixed = Table.Cell(blocks: [.paragraph(.init(spans: [.text("label")])), .image(image)])
        let table = TableMapper.content(caption: nil, headers: [self.cell("h")], alignments: nil, rows: [[mixed]])
        #expect(table.rows[0][0].elements == [.text(AttributedString("label")), .image(image)])
    }

    @Test("unknown cell block is dropped")
    func unknownBlockDropped() {
        let mixed = Table.Cell(blocks: [.unknown, .paragraph(.init(spans: [.text("keep")]))])
        let table = TableMapper.content(caption: nil, headers: [self.cell("h")], alignments: nil, rows: [[mixed]])
        #expect(table.rows[0][0].elements == [.text(AttributedString("keep"))])
    }

    // MARK: - Delta reconstruction

    @Test("deltas reconstruct the same table as the authoritative components")
    func deltasMatchAuthoritative() {
        let deltas: [PartDelta.TableDelta] = [
            .start(.init(headers: [self.cell("H1"), self.cell("H2")], alignments: [.left, .right], caption: "cap")),
            .appendRow([self.cell("a"), self.cell("b")]),
            .appendRow([self.cell("c"), self.cell("d")])
        ]
        let authoritative = TableMapper.content(
            caption: "cap",
            headers: [self.cell("H1"), self.cell("H2")],
            alignments: [.left, .right],
            rows: [[self.cell("a"), self.cell("b")], [self.cell("c"), self.cell("d")]]
        )
        #expect(TableMapper.content(deltas) == authoritative)
    }

    @Test("table deltas with no start return nil")
    func deltaNoStart() {
        #expect(TableMapper.content([.appendRow([self.cell("a")])]) == nil)
    }
}

private extension TableMapperTests {

    /// A single-paragraph text cell.
    func cell(_ text: String) -> Table.Cell {
        Table.Cell(blocks: [.paragraph(.init(spans: [.text(text)]))])
    }
}
