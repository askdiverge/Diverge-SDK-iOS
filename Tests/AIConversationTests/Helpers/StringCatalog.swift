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

    static func strings() throws -> [String: [String: Any]] {
        let url = try #require(Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"))
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
