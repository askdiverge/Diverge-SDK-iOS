//
//  StringCatalog.swift
//  AIConversationTests
//

import Foundation
import Testing
@testable import AIConversation

/// Localisation coverage, asserted against the resource bundle the SDK actually ships.
///
/// The two build systems ship the catalog differently: SwiftPM copies `Localizable.xcstrings` in
/// verbatim, while Xcode compiles it into `<locale>.lproj/Localizable.strings` and ships no
/// catalog at all. Read whichever form is present so the same contract holds under `swift test`
/// and the `xcodebuild test` CI runs.
enum StringCatalog {

    static let locales: Set<String> = [
        "da", "de", "de-AT", "de-CH", "en", "et", "fi", "fo", "fr", "is", "lt", "lv", "nb", "nl", "pl", "sv"
    ]

    /// Asserts every key ships a translation in each of ``locales``.
    static func expectKeysInEveryLocale(_ keys: [String]) throws {
        let translated = try Self.localesByKey()
        for key in keys {
            let locales = try #require(translated[key], "\(key) missing from the string catalog")
            #expect(locales == Self.locales, "\(key) is not translated everywhere")
        }
    }

    /// Which locales carry a translation, per key.
    static func localesByKey() throws -> [String: Set<String>] {
        if let catalog = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings") {
            return try Self.readCatalog(at: catalog)
        }
        return try Self.readCompiledTables()
    }

    /// SwiftPM — the catalog JSON lists its locales per key.
    private static func readCatalog(at url: URL) throws -> [String: Set<String>] {
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        return strings.mapValues { entry -> Set<String> in
            guard let localizations = entry["localizations"] as? [String: Any] else { return [] }
            return Set(localizations.keys)
        }
    }

    /// Xcode — one compiled table per locale, each a binary plist of key → translation.
    private static func readCompiledTables() throws -> [String: Set<String>] {
        var localesByKey: [String: Set<String>] = [:]
        for locale in Self.locales {
            let url = try #require(
                Bundle.module.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: locale
                ),
                "\(locale).lproj/Localizable.strings is missing from the resource bundle"
            )
            let table = try #require(
                NSDictionary(contentsOf: url) as? [String: String],
                "\(locale) ships a Localizable.strings that is not a key/value table"
            )
            for key in table.keys {
                localesByKey[key, default: []].insert(locale)
            }
        }
        return localesByKey
    }
}
