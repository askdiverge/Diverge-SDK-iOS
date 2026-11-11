//
//  BulletedText.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// A bubble's text. ``RichTextParser`` flattens a bullet list into lines that open with its marker,
/// and `Text` has no hanging indent, so each bullet is laid out as a glyph beside its line and
/// wrapped lines align under the text. A message without bullets stays one `Text`. While a reply
/// types in, each line reveals from its own place in the text, so the lines type one after another.
struct BulletedText: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.typewriterReveal) private var typewriterReveal

    let text: AttributedString

    var body: some View {
        let lines = Self.lines(of: self.text)
        if lines.contains(where: \.isBullet) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.isBullet {
                        HStack(alignment: .firstTextBaseline, spacing: self.appearance.spacing.units(1)) {
                            self.typed(Text(verbatim: "•"), from: line.offset + Self.bulletGlyphOffset)
                                .accessibilityHidden(true)
                            self.typed(Text(line.text), from: line.offset + RichTextParser.bulletMarker.count)
                        }
                        .padding(.leading, self.appearance.spacing.units(2))
                    } else {
                        self.typed(Text(line.text), from: line.offset)
                    }
                }
            }
        } else {
            Text(self.text)
        }
    }

    /// `text` as the typing reveals it, starting at character `offset` of the whole text.
    @ViewBuilder
    private func typed(_ text: Text, from offset: Int) -> some View {
        if let typewriterReveal {
            text.textRenderer(TypewriterRenderer(visibleCount: typewriterReveal - Double(offset)))
        } else {
            text
        }
    }
}

extension BulletedText {

    /// One line of the text, without its bullet marker.
    struct Line: Equatable {
        let text: AttributedString
        let isBullet: Bool
        /// Where the line, marker included, starts in the whole text, in characters.
        let offset: Int
    }

    /// Where the bullet glyph sits in ``RichTextParser/bulletMarker``, in characters.
    nonisolated static let bulletGlyphOffset = RichTextParser.bulletMarker.prefix { $0 != "•" }.count

    /// Splits `text` at its line breaks, keeping each line's styling.
    nonisolated static func lines(of text: AttributedString) -> [Line] {
        var offset = 0
        return text.characters.split(separator: "\n", omittingEmptySubsequences: false).map { characters in
            let line = AttributedString(text[characters.startIndex..<characters.endIndex])
            defer { offset += characters.count + 1 }
            guard String(line.characters).hasPrefix(RichTextParser.bulletMarker) else {
                return Line(text: line, isBullet: false, offset: offset)
            }
            let start = line.index(line.startIndex, offsetByCharacters: RichTextParser.bulletMarker.count)
            return Line(text: AttributedString(line[start...]), isBullet: true, offset: offset)
        }
    }
}
