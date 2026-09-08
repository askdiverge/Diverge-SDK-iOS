//
//  LivechatClientContext.swift
//  AIConversationEngine
//

import Foundation

/// Optional client environment on `POST /livechat/handover` — shown to agents while waiting.
///
/// Maps onto the public `client_context` object. Native apps reuse `browser` /
/// `browser_version` for the host app name and short version (no separate `app_version` field).
/// [API ref](https://docs.dialoge.ai/api#operation/Livechat_requestHandover)
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
        self.browser = Self.truncated(browser, max: Self.fieldMax)
        self.browserLanguage = Self.truncated(browserLanguage, max: Self.fieldMax)
        self.browserVersion = Self.truncated(browserVersion, max: Self.fieldMax)
        self.currentPageUrl = Self.truncated(currentPageUrl, max: Self.pageMax)
        self.language = Self.truncated(language, max: Self.fieldMax)
        self.os = Self.truncated(os, max: Self.fieldMax)
    }

    /// Snapshot of the host process for a handover request. Always includes `os`
    /// (`iOS` / `macOS`); other keys are omitted when blank.
    ///
    /// - Parameter page: Optional `contextProvider` string (path or URL), capped at 2048.
    package static func native(
        page: String?,
        bundle: Bundle = .main,
        locale: Locale = .current,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> LivechatClientContext {
        #if os(macOS)
        let osName = "macOS"
        #else
        let osName = "iOS"
        #endif
        let info = bundle.infoDictionary
        let appName = info?["CFBundleName"] as? String
        let appVersion = info?["CFBundleShortVersionString"] as? String
        let browserLanguage = preferredLanguages.first ?? locale.identifier
        let languageCode: String?
        if let code = locale.language.languageCode?.identifier {
            languageCode = code
        } else {
            languageCode = locale.identifier.split(separator: "_").first.map(String.init)
        }
        return LivechatClientContext(
            browser: appName,
            browserLanguage: browserLanguage,
            browserVersion: appVersion,
            currentPageUrl: page,
            language: languageCode,
            os: osName
        )
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.browser, forKey: .browser)
        try container.encodeIfPresent(self.browserLanguage, forKey: .browserLanguage)
        try container.encodeIfPresent(self.browserVersion, forKey: .browserVersion)
        try container.encodeIfPresent(self.currentPageUrl, forKey: .currentPageUrl)
        try container.encodeIfPresent(self.language, forKey: .language)
        try container.encodeIfPresent(self.os, forKey: .os)
    }

    private enum CodingKeys: String, CodingKey {
        case browser, browserLanguage, browserVersion, currentPageUrl, language, os
    }

    private static let fieldMax = 255
    private static let pageMax = 2048

    private static func truncated(_ value: String?, max: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.count <= max { return trimmed }
        return String(trimmed.prefix(max))
    }
}
