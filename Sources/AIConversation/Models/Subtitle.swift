//
//  Subtitle.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-25.
//

import Foundation
import SwiftUI
import AIConversationEngine

/// The header's disclaimer copy, composed into its rendered form at bootstrap.
struct Subtitle {
    let attributedText: AttributedString
}

extension Subtitle {

    /// Composes the config's subtitle — body copy with the link folded in as an underlined,
    /// tappable run. Either part may be absent; a link following text is spaced off from it. The
    /// copy's `[label](url)` links and `**bold**` render as they do on the web widget.
    init(_ subtitle: ChatConfig.Display.Subtitle) {
        var composed = AttributedString()

        if let text = subtitle.text {
            composed += Self.inlineMarkdown(text)
        }

        if let link = subtitle.link {
            if !composed.characters.isEmpty {
                composed += AttributedString(" ")
            }
            composed += Self.linkRun(link.text, url: link.url)
        }

        self.attributedText = composed
    }

    private static func linkRun(_ text: some StringProtocol, url: URL) -> AttributedString {
        var run = AttributedString(String(text))
        run.link = url
        run.underlineStyle = .single
        return run
    }
}

// MARK: - Inline Markdown

private extension Subtitle {

    /// The web widget's inline Markdown for the subtitle: `[label](url)` links, and `**bold**` in
    /// the text between them. A link opens only with a URL the web widget would open; any other
    /// keeps its label as plain text.
    static func inlineMarkdown(_ text: String) -> AttributedString {
        var composed = AttributedString()
        var rest = text[...]
        while let link = rest.firstMatch(of: /\[([^\]]+)\]\(([^)]+)\)/) {
            composed += Self.bold(rest[..<link.range.lowerBound])
            let (label, target) = (link.output.1, link.output.2)
            if let url = Self.webURL(target) {
                composed += Self.linkRun(label, url: url)
            } else {
                composed += AttributedString(String(label))
            }
            rest = rest[link.range.upperBound...]
        }
        return composed + Self.bold(rest)
    }

    /// The text with each `**bold**` span as strong emphasis.
    static func bold(_ text: Substring) -> AttributedString {
        var composed = AttributedString()
        var rest = text
        while let span = rest.firstMatch(of: /\*\*([^*]+)\*\*/) {
            composed += AttributedString(String(rest[..<span.range.lowerBound]))
            var emphasis = AttributedString(String(span.output.1))
            emphasis.inlinePresentationIntent = .stronglyEmphasized
            composed += emphasis
            rest = rest[span.range.upperBound...]
        }
        return composed + AttributedString(String(rest))
    }

    /// The link's target as an absolute http or https URL, written as the web widget accepts it:
    /// no whitespace, control characters, quotes, angle brackets or backticks.
    static func webURL(_ target: Substring) -> URL? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { "\"'<>`".contains($0) }),
              let url = URL(string: trimmed, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil else {
            return nil
        }
        return url
    }
}
