//
//  SubtitleTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("Subtitle — the config's disclaimer copy")
struct SubtitleTests {

    @Test("a Markdown link renders as a tappable run under its label")
    func markdownLinkBecomesRun() throws {
        let text = Self.rendered("Läs mer i vår [integritetspolicy](https://www.boozt.com/se/sv/policy).")

        #expect(String(text.characters) == "Läs mer i vår integritetspolicy.")
        let run = try #require(text.runs.first { $0.link != nil })
        #expect(String(text[run.range].characters) == "integritetspolicy")
        #expect(run.link == URL(string: "https://www.boozt.com/se/sv/policy"))
    }

    @Test("bold markers render as strong emphasis")
    func boldBecomesEmphasis() throws {
        let text = Self.rendered("**Obs:** rabatten gäller")

        #expect(String(text.characters) == "Obs: rabatten gäller")
        let run = try #require(text.runs.first { $0.inlinePresentationIntent == .stronglyEmphasized })
        #expect(String(text[run.range].characters) == "Obs:")
    }

    @Test("a link to anything but an absolute http or https URL keeps its label as plain text")
    func otherLinksStayText() {
        let text = Self.rendered(
            "Ring [oss](tel:123), läs [villkoren](/se/villkor), hämta [filen](ftp://example.com/fil) eller [här](javascript:alert)"
        )

        #expect(String(text.characters) == "Ring oss, läs villkoren, hämta filen eller här")
        #expect(text.runs.allSatisfy { $0.link == nil })
    }

    @Test("copy without complete markup stays as written, and the configured link still follows it")
    func incompleteMarkupAndLink() throws {
        let terms = try #require(URL(string: "https://example.com/terms"))
        let text = Subtitle(.init(text: "Priser i **SEK [se", link: .init(text: "Villkor", url: terms))).attributedText

        #expect(String(text.characters) == "Priser i **SEK [se Villkor")
        let run = try #require(text.runs.first { $0.link != nil })
        #expect(String(text[run.range].characters) == "Villkor")
    }
}

private extension SubtitleTests {

    static func rendered(_ text: String) -> AttributedString {
        Subtitle(.init(text: text, link: nil)).attributedText
    }
}
