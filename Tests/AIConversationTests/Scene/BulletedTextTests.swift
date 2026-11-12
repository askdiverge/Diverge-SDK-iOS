//
//  BulletedTextTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("BulletedText — lines")
struct BulletedTextTests {

    @Test("a bullet list splits into lines without their marker")
    func bulletsSplit() {
        let text = AttributedString("\(RichTextParser.bulletMarker)one\n\(RichTextParser.bulletMarker)two")

        #expect(BulletedText.lines(of: text) == [
            .init(text: AttributedString("one"), isBullet: true, offset: 0),
            .init(text: AttributedString("two"), isBullet: true, offset: RichTextParser.bulletMarker.count + 4)
        ])
    }

    @Test("each line knows where it starts in the whole text, so typing reveals the lines in order")
    func linesKnowTheirOffsets() {
        let text = AttributedString("intro\n\(RichTextParser.bulletMarker)one\n\noutro")

        #expect(BulletedText.lines(of: text).map(\.offset) == [0, 6, 6 + RichTextParser.bulletMarker.count + 4, 7 + RichTextParser.bulletMarker.count + 4])
        #expect(BulletedText.bulletGlyphOffset == 3)
    }

    @Test("paragraphs around a list stay plain lines")
    func paragraphsStayPlain() {
        let text = AttributedString("intro\n\(RichTextParser.bulletMarker)one\noutro")

        #expect(BulletedText.lines(of: text).map(\.isBullet) == [false, true, false])
    }

    @Test("a bullet keeps its styling")
    func bulletKeepsStyling() {
        var bold = AttributedString("bold")
        bold.inlinePresentationIntent = .stronglyEmphasized
        let text = AttributedString(RichTextParser.bulletMarker) + bold

        let line = BulletedText.lines(of: text).first

        #expect(line?.isBullet == true)
        #expect(line?.text == bold)
    }

    @Test("text with no bullets is one plain line")
    func noBullets() {
        #expect(BulletedText.lines(of: AttributedString("hello")) == [
            .init(text: AttributedString("hello"), isBullet: false, offset: 0)
        ])
    }
}
