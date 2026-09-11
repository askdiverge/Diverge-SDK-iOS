//
//  PrivacyExportAccessibilityTests.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

@Suite("Privacy export — accessibility / catalog")
struct PrivacyExportAccessibilityTests {

    @Test("download catalog keys exist in every locale")
    func catalogKeysInEveryLocale() throws {
        try StringCatalog.expectKeysInEveryLocale([
            "privacy.downloadEntry",
            "privacy.downloadError"
        ])
    }
}
