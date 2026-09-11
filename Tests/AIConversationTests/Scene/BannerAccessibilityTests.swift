//
//  BannerAccessibilityTests.swift
//  AIConversationTests
//

import Testing
@testable import AIConversation

@Suite("Banner accessibility catalog")
struct BannerAccessibilityTests {

    @Test("banner.dismiss and banner.cta resolve and exist in every locale")
    func catalogKeys() throws {
        #expect(!L10n.bannerDismiss.string.isEmpty)
        #expect(!L10n.bannerCTA.string.isEmpty)
        try StringCatalog.expectKeysInEveryLocale(["banner.dismiss", "banner.cta"])
    }
}
