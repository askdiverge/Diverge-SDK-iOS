//
//  RichTextParserTests.swift
//  AIConversationTests
//
//  Created by Daniel Wennberg on 2026-06-17.
//

import Foundation
import Testing
@testable import AIConversationEngine

@Suite("RichTextParser — rich_text → AttributedString")
struct RichTextParserTests {

    // MARK: - Spans (inline styling)

    @Test("plain text maps to an unstyled run")
    func plainText() {
        #expect(RichTextParser.attributedText(self.paragraph(.text("hello"))) == AttributedString("hello"))
    }

    @Test("bold maps to .stronglyEmphasized")
    func bold() {
        var expected = AttributedString("strong")
        expected.inlinePresentationIntent = .stronglyEmphasized
        #expect(RichTextParser.attributedText(self.paragraph(.bold("strong"))) == expected)
    }

    @Test("strike maps to .strikethrough")
    func strike() {
        var expected = AttributedString("gone")
        expected.inlinePresentationIntent = .strikethrough
        #expect(RichTextParser.attributedText(self.paragraph(.strike("gone"))) == expected)
    }

    @Test("link maps to a .link URL run")
    func link() {
        var expected = AttributedString("site")
        expected.link = URL(string: "https://boozt.com")
        let result = RichTextParser.attributedText(
            self.paragraph(.link(text: "site", url: URL(string: "https://boozt.com")!))
        )
        #expect(result == expected)
    }

    @Test("spans in a paragraph concatenate in order, keeping their styling")
    func concatenatedSpans() {
        var bold = AttributedString("b")
        bold.inlinePresentationIntent = .stronglyEmphasized
        let expected = AttributedString("a ") + bold + AttributedString(" c")
        #expect(RichTextParser.attributedText(self.paragraph(.text("a "), .bold("b"), .text(" c"))) == expected)
    }

    @Test("unknown span is dropped, siblings survive")
    func unknownSpanDropped() {
        #expect(RichTextParser.attributedText(self.paragraph(.text("keep"), .unknown)) == AttributedString("keep"))
    }

    // MARK: - Blocks

    @Test("paragraphs join with a newline")
    func paragraphsJoinWithNewline() {
        let rich = RichText(partId: "", blocks: [
            .paragraph(.init(spans: [.text("one")])),
            .paragraph(.init(spans: [.text("two")]))
        ])
        #expect(RichTextParser.attributedText(rich) == AttributedString("one\ntwo"))
    }

    @Test("bullet list prefixes each item with the marker, items newline-joined")
    func bulletList() {
        let rich = RichText(partId: "", blocks: [
            .bulletList(.init(items: [
                .init(spans: [.text("first")]),
                .init(spans: [.text("second")])
            ]))
        ])
        let marker = RichTextParser.bulletMarker
        let expected = marker + AttributedString("first") + AttributedString("\n") + marker + AttributedString("second")
        #expect(RichTextParser.attributedText(rich) == expected)
    }

    @Test("empty content returns nil")
    func emptyReturnsNil() {
        #expect(RichTextParser.attributedText(RichText(partId: "", blocks: [])) == nil)
        #expect(RichTextParser.attributedText(self.paragraph()) == nil)
    }

    // MARK: - Delta reconstruction

    @Test("deltas reconstruct the same AttributedString as the authoritative part")
    func deltasMatchAuthoritative() {
        let deltas: [PartDelta.RichTextDelta] = [
            .start,
            .startBlock(index: 0, type: .paragraph),
            .appendText(index: 0, text: "a "),
            .appendSpan(index: 0, span: .bold("b")),
            .endBlock(index: 0)
        ]
        var bold = AttributedString("b")
        bold.inlinePresentationIntent = .stronglyEmphasized
        #expect(RichTextParser.attributedText(deltas) == AttributedString("a ") + bold)
    }

    @Test("appendItem reconstructs a bullet item with its marker")
    func deltaBulletItem() {
        let deltas: [PartDelta.RichTextDelta] = [
            .start,
            .startBlock(index: 0, type: .bulletList),
            .appendItem(index: 0, item: .init(spans: [.text("x")]))
        ]
        #expect(RichTextParser.attributedText(deltas) == RichTextParser.bulletMarker + AttributedString("x"))
    }

    @Test("a delta targeting a block index that was never opened is ignored, not a crash")
    func deltaOutOfOrderIgnored() {
        #expect(RichTextParser.attributedText([.appendText(index: 5, text: "orphan")]) == nil)
    }
}

private extension RichTextParserTests {

    /// A single-paragraph rich text built from the given spans.
    func paragraph(_ spans: RichText.Span...) -> RichText {
        RichText(partId: "", blocks: [.paragraph(.init(spans: spans))])
    }
}
