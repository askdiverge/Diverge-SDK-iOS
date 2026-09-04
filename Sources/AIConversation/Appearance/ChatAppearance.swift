//
//  ChatAppearance.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-23.
//

import Foundation
import SwiftUI
import AIConversationEngine

/// The chat's ambient appearance — theme palette and spacing grid.
struct ChatAppearance {

    let theme: Theme
    let spacing = Spacing()

    /// The registered custom font family; nil falls the chat back to the system font.
    let fontFamily: String?

    struct Theme {
        // Wire-driven — parsed from the config.
        let accent: Color
        let primaryText: Color
        let userBubble: Color
        let userBubbleText: Color
        let botSurface: Color
        let background: Color
        let secondaryText: Color
        let discountPrice: Color
        let inputText: Color
        let inputPlaceholder: Color
        let inputBackground: Color?
        let sendIcon: Color?
        let toolbarIcon: Color
        let botSurfaceBorder: Color?
        let userBubbleBorder: Color?
        let inputBorder: Color?
        /// Ordered color stops for the assistant thinking-state border animation; empty when unset.
        let thinkingBorderGradient: [Color]

        // TODO: not yet wire-driven — SDK constants until the config carries them.
        let errorBackground: Color
        let errorForeground: Color
        let accentForeground: Color
        let destructive: Color
        let outline: Color
    }

    /// The chat's 4-pt spacing grid. `spacing.units(2)` → 8.
    struct Spacing {
        let unit: CGFloat = 4
        func units(_ count: UInt) -> CGFloat { self.unit * CGFloat(count) }
    }
}

extension ChatAppearance {

    /// Empty appearance carrying the default theme — used until remote config lands, and what
    /// the error screen themes from when there's no config at all.
    static let `default` = ChatAppearance(theme: .default, fontFamily: nil)
}

extension ChatAppearance.Theme {

    // TODO: SDK default palette until config supplies / extends the theme.
    static let `default` = ChatAppearance.Theme(
        accent: Color(hex: "#18191B") ?? .black,
        primaryText: Color(hex: "#121212") ?? .primary,
        userBubble: Color(hex: "#1A1A1A") ?? .black,
        userBubbleText: Color(hex: "#FBF6F1") ?? .white,
        botSurface: Color(hex: "#F5F5F5") ?? .gray,
        background: Color(hex: "#FFFFFF") ?? .white,
        secondaryText: Color(hex: "#707070") ?? .secondary,
        discountPrice: Color(hex: "#E0001A") ?? .red,
        inputText: Color(hex: "#333333") ?? .primary,
        inputPlaceholder: Color(hex: "#999999") ?? .secondary,
        inputBackground: nil,
        sendIcon: nil,
        toolbarIcon: Color(hex: "#18191B") ?? .primary,
        botSurfaceBorder: Color(hex: "#B8B9BE") ?? .gray,
        userBubbleBorder: nil,
        inputBorder: Color(hex: "#B8B9BE") ?? .gray,
        thinkingBorderGradient: [],
        errorBackground: Color(hex: "#FFF0F1") ?? .gray,
        errorForeground: Color(hex: "#42090D") ?? .red,
        accentForeground: Color(hex: "#FBF6F1") ?? .white,
        destructive: Color(hex: "#E0001A") ?? .red,
        outline: Color(hex: "#92949B") ?? .gray
    )
}

extension ChatAppearance {

    /// Resolves the config's theme, falling back to the default palette on unparseable hex.
    init(_ config: ChatConfig, fontFamily: String?) {
        self.theme = Theme(config.theme) ?? .default
        self.fontFamily = fontFamily
    }
}

extension ChatAppearance {

    /// The chat's SF Symbols
    enum Symbol {
        /// submits the drafted message.
        static let send = Image(systemName: "arrow.up")

        /// return control — jumps back to the latest message.
        static let scrollToBottom = Image(systemName: "arrow.down")

        /// toolbar — starts a fresh conversation.
        static let reset = Image(systemName: "arrow.trianglehead.2.counterclockwise.rotate.90")

        /// leading control & opens Privacy & Data.
        static let privacy = Image(systemName: "checkmark.shield")

        /// deletes visitor data.
        static let delete = Image(systemName: "trash")

        /// dismisses the sheet.
        static let close = Image(systemName: "xmark")

        /// retries the failed bootstrap.
        static let retry = Image(systemName: "arrow.clockwise")

        /// the checked-state mark.
        static let checkmark = Image(systemName: "checkmark")

        /// leads the transient error/notice bar.
        static let notice = Image(systemName: "exclamationmark.circle")

        /// placeholder until design supplies a bespoke glyph.
        static let errorHero = Image(systemName: "exclamationmark.circle")

        /// accessory — signals the row opens an external URL.
        static let externalLink = Image(systemName: "arrow.up.right")

        /// accessory — discloses the delete sheet.
        static let disclosure = Image(systemName: "chevron.right")
    }

    /// The chat's base font at `size`. Uses the config's custom family when it resolved — its faces
    /// resolve per `weight` and per inline emphasis — otherwise the system font.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontFamily = self.fontFamily {
            Font.custom(fontFamily, size: size).weight(weight)
        } else {
            Font.system(size: size, weight: weight)
        }
    }
}

private extension ChatAppearance.Theme {

    /// Builds the palette only if every required color parses; a single bad hex yields `nil` so the
    /// caller substitutes the default palette instead of a half-applied theme. The optional borders
    /// are lenient — absent or unparseable means no border for that surface, not a whole-theme failure.
    init?(_ theme: ChatConfig.Theme) {

        guard
            let accent = Color(hex: theme.brand.primaryColor),
            let primaryText = Color(hex: theme.messages.assistant.textColor),
            let userBubble = Color(hex: theme.messages.user.backgroundColor),
            let userBubbleText = Color(hex: theme.messages.user.textColor),
            let botSurface = Color(hex: theme.messages.assistant.backgroundColor),
            let background = Color(hex: theme.surface.backgroundColor),
            let secondaryText = Color(hex: theme.surface.mutedTextColor),
            let discountPrice = Color(hex: theme.productCard.discountPriceColor),
            let inputText = Color(hex: theme.input.textColor),
            let inputPlaceholder = Color(hex: theme.input.placeholderColor),
            let toolbarIcon = Color(hex: theme.header.button.iconColor)
        else {
            return nil
        }

        self.accent = accent
        self.primaryText = primaryText
        self.userBubble = userBubble
        self.userBubbleText = userBubbleText
        self.botSurface = botSurface
        self.background = background
        self.secondaryText = secondaryText
        self.discountPrice = discountPrice
        self.inputText = inputText
        self.inputPlaceholder = inputPlaceholder
        self.toolbarIcon = toolbarIcon
        self.inputBackground = theme.input.backgroundColor.flatMap(Color.init(hex:))
        self.sendIcon = theme.input.sendButton.iconColor.flatMap(Color.init(hex:))
        self.botSurfaceBorder = theme.messages.assistant.borderColor.flatMap(Color.init(hex:))
        self.userBubbleBorder = theme.messages.user.borderColor.flatMap(Color.init(hex:))
        self.inputBorder = theme.input.borderColor.flatMap(Color.init(hex:))
        self.thinkingBorderGradient = theme.messages.assistant.thinkingBorderGradient.compactMap(Color.init(hex:))

        // Not yet wire-driven — borrow the SDK constants until the config carries them.

        // Notice/error bar fill; also the checkbox error state.
        self.errorBackground = Self.default.errorBackground
        // Notice/error bar icon + text.
        self.errorForeground = Self.default.errorForeground
        // Light foreground on filled action buttons (send, retry, delete-confirm). Reuse candidate: userBubbleText.
        self.accentForeground = Self.default.accentForeground
        // Destructive actions — delete button and the checkbox.
        self.destructive = Self.default.destructive
        // Neutral outline for form controls — checkbox and secondary-button borders.
        self.outline = Self.default.outline
    }
}
