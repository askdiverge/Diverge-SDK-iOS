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

    @Test(
        "a size between two text styles takes the smaller, at every boundary",
        arguments: [
            (8, Font.TextStyle.caption2),
            (11.9, .caption2),
            (12.9, .caption),
            (14, .footnote),
            (14.9, .footnote),
            (15.9, .subheadline),
            (16.9, .callout),
            (19.9, .body),
            (21.9, .title3),
            (27.9, .title2),
            (33.9, .title),
            (48, .largeTitle)
        ]
    )
    func betweenSizesTakeTheSmallerStyle(size: CGFloat, style: Font.TextStyle) {
        #expect(ChatAppearance.default.font(size: size) == .system(style, weight: .regular))
    }

    @Test("a weight carries through")
    func weightCarriesThrough() {
        #expect(ChatAppearance.default.font(size: 13, weight: .bold) == .system(.footnote, weight: .bold))
    }
}
