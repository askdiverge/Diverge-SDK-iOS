//
//  ChatAppearanceFontTests.swift
//  AIConversationTests
//

import SwiftUI
import Testing
@testable import AIConversation

@Suite("ChatAppearance — fonts")
struct ChatAppearanceFontTests {

    @Test(
        "with no custom family each size is the text style of that size, so it scales with Dynamic Type",
        arguments: [
            (11, Font.TextStyle.caption2),
            (12, .caption),
            (13, .footnote),
            (15, .subheadline),
            (16, .callout),
            (17, .body),
            (20, .title3),
            (22, .title2),
            (28, .title),
            (34, .largeTitle)
        ]
    )
    func systemFontScales(size: CGFloat, style: Font.TextStyle) {
        #expect(ChatAppearance.default.font(size: size) == .system(style, weight: .regular))
    }

    @Test("a weight carries through")
    func weightCarriesThrough() {
        #expect(ChatAppearance.default.font(size: 13, weight: .bold) == .system(.footnote, weight: .bold))
    }
}
