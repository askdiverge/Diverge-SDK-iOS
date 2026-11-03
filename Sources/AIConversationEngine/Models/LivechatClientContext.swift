//
//  LivechatClientContext.swift
//  AIConversationEngine
//

import Foundation

/// The `client_context` on `POST /livechat/handover`, shown to agents while the visitor waits.
///
/// Each field keeps the meaning the API gives it; ``native(page:locale:preferredLanguages:)`` fills
/// the ones a native client knows. Blank values are dropped and long ones truncated to the API's
/// limits, so a context never fails the handover.
/// [API ref](https://docs.askdiverge.ai/api#model/livechathandoverrequest)
package struct LivechatClientContext: Encodable, Sendable, Equatable {

    package let browser: String?
    package let browserLanguage: String?
    package let browserVersion: String?
    package let currentPageUrl: String?
    package let language: String?
    package let os: String?

    package init(
        browser: String? = nil,
        browserLanguage: String? = nil,
        browserVersion: String? = nil,
        currentPageUrl: String? = nil,
        language: String? = nil,
        os: String? = nil
    ) {
        self.browser = Self.clamped(browser, to: Self.fieldMax)
        self.browserLanguage = Self.clamped(browserLanguage, to: Self.fieldMax)
        self.browserVersion = Self.clamped(browserVersion, to: Self.fieldMax)
        self.currentPageUrl = Self.clamped(currentPageUrl, to: Self.pageMax)
        self.language = Self.clamped(language, to: Self.fieldMax)
        self.os = Self.clamped(os, to: Self.fieldMax)
    }

    /// The context a native client sends: the device's UI language as `browser_language`, the
    /// host's page context as `current_page_url`, and `os` (`iOS` / `macOS`).
    ///
    /// - Parameter page: The host's `contextProvider` value (a path or URL), if any.
    package static func native(
        page: String?,
        locale: Locale = .current,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> LivechatClientContext {
        #if os(macOS)
        let osName = "macOS"
        #else
        let osName = "iOS"
        #endif
        return LivechatClientContext(
            browserLanguage: preferredLanguages.first ?? locale.identifier,
            currentPageUrl: page,
            os: osName
        )
    }

    private static let fieldMax = 255
    private static let pageMax = 2048

    /// Caps `value` at `max` UTF-16 code units, the strictest unit a server may count `maxLength`
    /// in, keeping whole characters.
    private static func clamped(_ value: String?, to max: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.utf16.count <= max { return trimmed }
        var result = ""
        var units = 0
        for character in trimmed {
            units += character.utf16.count
            guard units <= max else { break }
            result.append(character)
        }
        return result
    }
}
