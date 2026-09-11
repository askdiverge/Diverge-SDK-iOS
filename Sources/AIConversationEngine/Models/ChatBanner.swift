//
//  ChatBanner.swift
//  AIConversationEngine
//

import Foundation

/// An in-chat promo strip from `GET /api/v1/chat/banners`.
///
/// Schedule and URL matching are applied on the server. The SDK paints whatever
/// list comes back; missing optional fields decode leniently.
///
/// [API ref](https://docs.dialoge.ai/api#model/chat-banner)
package struct ChatBanner: Decodable, Sendable, Equatable, Identifiable {

    package enum CTAStyle: String, Decodable, Sendable, Equatable {
        case link
        case button
    }

    package let id: String
    package let message: String
    package let backgroundColor: String?
    package let textColor: String?
    package let ctaUrl: String?
    package let ctaLabel: String?
    package let ctaStyle: CTAStyle?
    package let dismissible: Bool

    package init(
        id: String,
        message: String,
        backgroundColor: String? = nil,
        textColor: String? = nil,
        ctaUrl: String? = nil,
        ctaLabel: String? = nil,
        ctaStyle: CTAStyle? = nil,
        dismissible: Bool = false
    ) {
        self.id = id
        self.message = message
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.ctaUrl = ctaUrl
        self.ctaLabel = ctaLabel
        self.ctaStyle = ctaStyle
        self.dismissible = dismissible
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.message = try container.decode(String.self, forKey: .message)
        self.backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        self.textColor = try container.decodeIfPresent(String.self, forKey: .textColor)
        self.ctaUrl = try container.decodeIfPresent(String.self, forKey: .ctaUrl)
        self.ctaLabel = try container.decodeIfPresent(String.self, forKey: .ctaLabel)
        // Unknown / blank style strings → nil (treated as link chrome at the view).
        // Decode as String first — `decodeIfPresent(CTAStyle.self)` throws on "pill".
        let rawStyle = try container.decodeIfPresent(String.self, forKey: .ctaStyle)
        self.ctaStyle = rawStyle.flatMap(CTAStyle.init(rawValue:))
        self.dismissible = try container.decodeIfPresent(Bool.self, forKey: .dismissible) ?? false
    }

    /// Content fingerprint matching the web widget — dismiss hides until content changes
    /// or a new ``AIChat`` / `makeView()` session.
    package var contentFingerprint: String {
        [
            self.message,
            self.backgroundColor ?? "",
            self.textColor ?? "",
            self.ctaUrl ?? "",
            self.ctaLabel ?? "",
            self.ctaStyle?.rawValue ?? "",
            self.dismissible ? "1" : "0"
        ].joined(separator: "|")
    }

    /// Absolute http(s) CTA only — relative paths and `javascript:` are dropped (no shop base on iOS).
    package var sanitizedCTAURL: URL? {
        guard let raw = self.ctaUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    /// Trimmed CTA label, or `nil` when blank.
    package var trimmedCTALabel: String? {
        guard let label = self.ctaLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty
        else { return nil }
        return label
    }

    /// CTA renders only when both a sanitized http(s) URL and a non-empty label exist.
    package var showsCTA: Bool {
        self.sanitizedCTAURL != nil && self.trimmedCTALabel != nil
    }

    /// Blank body text is dropped — an empty coloured bar is not a banner.
    package var hasVisibleMessage: Bool {
        !self.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, message, backgroundColor, textColor, ctaUrl, ctaLabel, ctaStyle, dismissible
    }
}

/// Wire envelope for `GET /api/v1/chat/banners`.
package struct ChatBannerList: Decodable, Sendable, Equatable {
    package let banners: [ChatBanner]

    package init(banners: [ChatBanner]) {
        self.banners = banners.filter(\.hasVisibleMessage)
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded =
            try container.decodeIfPresent(LossyArray<ChatBanner>.self, forKey: .banners)?
            .elements ?? []
        self.banners = decoded.filter(\.hasVisibleMessage)
    }

    private enum CodingKeys: String, CodingKey {
        case banners
    }
}
