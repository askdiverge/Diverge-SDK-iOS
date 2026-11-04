//
//  BulletedText.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// A bubble's text. ``RichTextParser`` flattens a bullet list into lines that open with its marker,
/// and `Text` has no hanging indent, so each bullet is laid out as a glyph beside its line and
/// wrapped lines align under the text. A message without bullets stays one `Text`.
struct BulletedText: View {

    @Environment(\.appearance) private var appearance

    let text: AttributedString

    var body: some View {
        let lines = Self.lines(of: self.text)
        if lines.contains(where: \.isBullet) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if line.isBullet {
                        HStack(alignment: .firstTextBaseline, spacing: self.appearance.spacing.units(1)) {
                            Text(verbatim: "•")
                                .accessibilityHidden(true)
                            Text(line.text)
                        }
                        .padding(.leading, self.appearance.spacing.units(2))
                    } else {
                        Text(line.text)
                    }
                }
            }
        } else {
            Text(self.text)
        }
    }
}

extension BulletedText {

    /// One line of the text, without its bullet marker.
    struct Line: Equatable {
        let text: AttributedString
        let isBullet: Bool
    }

    /// Splits `text` at its line breaks, keeping each line's styling.
    nonisolated static func lines(of text: AttributedString) -> [Line] {
        text.characters.split(separator: "\n", omittingEmptySubsequences: false).map { characters in
            let line = AttributedString(text[characters.startIndex..<characters.endIndex])
            guard String(line.characters).hasPrefix(RichTextParser.bulletMarker) else {
                return Line(text: line, isBullet: false)
            }
            let start = line.index(line.startIndex, offsetByCharacters: RichTextParser.bulletMarker.count)
            return Line(text: AttributedString(line[start...]), isBullet: true)
        }
    }
}
