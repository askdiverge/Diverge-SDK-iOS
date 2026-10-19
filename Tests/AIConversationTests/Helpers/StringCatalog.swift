//
//  StringCatalog.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

enum StringCatalog {

    static let locales: Set<String> = [
        "da", "de", "de-AT", "de-CH", "en", "et", "fi", "fo", "fr", "is", "lt", "lv", "nb", "nl", "pl", "sv"
    ]

    /// Reads the source catalog JSON. SPM compiles `Localizable.xcstrings` into `.lproj`
    /// tables inside `DivergeSDK_AIConversation.bundle`, so the raw file is not available
    /// via `Bundle.module` at test time — walk from this file up to the package root instead.
    static func strings() throws -> [String: [String: Any]] {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Helpers
            .deletingLastPathComponent() // AIConversationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let url = packageRoot
            .appendingPathComponent("Sources/AIConversation/Resources/Localizable.xcstrings")
        try #require(
            FileManager.default.fileExists(atPath: url.path),
            "Localizable.xcstrings missing at \(url.path)"
        )
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try #require(root["strings"] as? [String: [String: Any]])
    }

    static func expectKeysInEveryLocale(_ keys: [String]) throws {
        let strings = try self.strings()
        for key in keys {
            let entry = try #require(
                strings[key]?["localizations"] as? [String: Any],
                "\(key) missing"
            )
            #expect(Set(entry.keys) == Self.locales, "\(key) is not translated everywhere")
        }
    }
}
