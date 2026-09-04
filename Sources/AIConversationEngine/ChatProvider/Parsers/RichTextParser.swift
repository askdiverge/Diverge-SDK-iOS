//
//  RichTextParser.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-11.
//

import Foundation

/// Formats a `RichText` into a single `AttributedString`.
///
/// Spans carry their real styling (bold, strike, link) as attribute runs,  styling is
/// semantic (`inlinePresentationIntent`), so the VM/theme decides the concrete font
/// Bullet lists render as markdown-style lines, each prefixed
/// with a `•`:in flowing-text mode the bullet is content, not a themed ornament, and
enum RichTextParser {

    static let bulletMarker = AttributedString("   •  ")

    /// Returns nil when the content is empty
    static func attributedText(_ richText: RichText) -> AttributedString? {
        let parts = richText.blocks.map(self.block)
        let text = self.joined(parts, separator: .init("\n"))
        return text.characters.isEmpty ? nil : text
    }

    private static func block(_ block: RichText.Block) -> AttributedString {
        switch block {
        case .paragraph(let paragraph):
            self.joined(paragraph.spans.compactMap(self.span))
        case .bulletList(let list):
            self.joined(
                list.items.map {
                    Self.bulletMarker + self.joined($0.spans.compactMap(self.span))
                },
                separator: .init("\n")
            )
        case .unknown:
            AttributedString()
        }
    }

    private static func span(_ span: RichText.Span) -> AttributedString? {
        switch span {
        case .text(let text): self.styled(text) { _ in }
        case .bold(let text): self.styled(text) { $0.inlinePresentationIntent = .stronglyEmphasized }
        case .strike(let text): self.styled(text) { $0.inlinePresentationIntent = .strikethrough }
        case .link(let text, let url): self.styled(text) { $0.link = url }
        case .unknown: nil
        }
    }

    private static func styled(
        _ text: String,
        apply: (inout AttributedString) -> Void
    ) -> AttributedString {
        var attributed = AttributedString(text)
        apply(&attributed)
        return attributed
    }

    /// Concatenates pieces (dropping empties), joining with `separator` between them.
    private static func joined(
        _ pieces: [AttributedString],
        separator: AttributedString = .init()
    ) -> AttributedString {
        let nonEmpty = pieces.filter { !$0.characters.isEmpty }
        guard let first = nonEmpty.first else { return AttributedString() }
        return nonEmpty.dropFirst().reduce(into: first) { result, piece in
            result += separator
            result += piece
        }
    }
}
