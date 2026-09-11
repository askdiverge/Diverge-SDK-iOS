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
///
/// Holds both the light and dark palettes from `/config` and exposes the active one as
/// ``theme``. Call ``with(colorScheme:)`` when the environment scheme (or a host override)
/// changes so views that read `appearance.theme.*` re-render without a config re-fetch.
struct ChatAppearance {

    /// Palette for light color schemes (`config.theme`).
    let light: Theme
    /// Palette for dark color schemes (`config.dark_theme`). Equals ``light`` when the
    /// chatbot has no dark theme configured, or when the dark hexes fail to parse.
    let dark: Theme
    /// The scheme that ``theme`` currently serves.
    let colorScheme: ColorScheme
    /// True when `/config` supplied a `dark_theme` that parsed and is not a clone of `theme`.
    /// System chrome (keyboard, pickers) follows this, not the host lock alone.
    let hasDistinctDarkPalette: Bool

    let spacing = Spacing()

    /// The registered custom font family; nil falls the chat back to the system font.
    let fontFamily: String?

    /// The active palette for the current ``colorScheme``.
    var theme: Theme {
        self.colorScheme == .dark ? self.dark : self.light
    }

    /// Chrome for `.preferredColorScheme`. A cloned / unconfigured `dark_theme` paints light,
    /// so this stays `.light` even when the host locked `.dark` or the environment is dark.
    var chromeColorScheme: ColorScheme {
        (self.colorScheme == .dark && self.hasDistinctDarkPalette) ? .dark : .light
    }

    /// Returns a copy that serves the other palette without re-parsing hexes.
    func with(colorScheme: ColorScheme) -> ChatAppearance {
        ChatAppearance(
            light: self.light,
            dark: self.dark,
            colorScheme: colorScheme,
            fontFamily: self.fontFamily,
            hasDistinctDarkPalette: self.hasDistinctDarkPalette
        )
    }

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
        /// Parsed header button fill when the config supplies a valid CSS colour.
        /// Painted behind close / reset toolbar glyphs; nil keeps the system chrome.
        let headerButtonBackground: Color?
        /// Ordered color stops for the assistant thinking-state border animation; empty when unset.
        let thinkingBorderGradient: [Color]
        /// Product CTA fill; nil → fall back to `accent` at the view.
        let productButtonBackground: Color?
        /// Whether the product CTA label is bold. Defaults to `true` when the config omits it.
        let productButtonBold: Bool

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

    init(
        light: Theme,
        dark: Theme,
        colorScheme: ColorScheme = .light,
        fontFamily: String?,
        hasDistinctDarkPalette: Bool = false
    ) {
        self.light = light
        self.dark = dark
        self.colorScheme = colorScheme
        self.fontFamily = fontFamily
        self.hasDistinctDarkPalette = hasDistinctDarkPalette
    }
}

extension ChatAppearance {

    /// Fallback palette for the error screen when bootstrap never landed a config. Light-only
    /// by design: the server clones light into `dark_theme` for unconfigured chatbots. Loading
    /// does not use this — it paints a system surface so dark-mode visitors do not flash white.
    static let `default` = ChatAppearance(
        light: .default,
        dark: .default,
        colorScheme: .light,
        fontFamily: nil,
        hasDistinctDarkPalette: false
    )
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
        headerButtonBackground: nil,
        thinkingBorderGradient: [],
        productButtonBackground: nil,
        productButtonBold: true,
        errorBackground: Color(hex: "#FFF0F1") ?? .gray,
        errorForeground: Color(hex: "#42090D") ?? .red,
        accentForeground: Color(hex: "#FBF6F1") ?? .white,
        destructive: Color(hex: "#E0001A") ?? .red,
        outline: Color(hex: "#92949B") ?? .gray
    )
}

extension ChatAppearance {

    /// Resolves light and dark themes from config. A broken light palette falls back to the
    /// SDK default; a broken dark palette falls back to the **parsed light** palette (not the
    /// SDK default), so a customer with a bad dark hex still sees their light brand colours.
    init(_ config: ChatConfig, fontFamily: String?, colorScheme: ColorScheme = .light) {
        let light = Theme(config.theme) ?? .default
        let parsedDark = Theme(config.darkTheme)
        let dark = parsedDark ?? light
        // Wire equality, not Color equality — a parsed-but-cloned dark_theme is not distinct.
        let hasDistinctDarkPalette = parsedDark != nil && config.darkTheme != config.theme
        self.init(
            light: light,
            dark: dark,
            colorScheme: colorScheme,
            fontFamily: fontFamily,
            hasDistinctDarkPalette: hasDistinctDarkPalette
        )
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

        /// Privacy & Data — downloads the visitor GDPR export.
        static let download = Image(systemName: "square.and.arrow.down")

        /// accessory — opens the system share sheet.
        static let share = Image(systemName: "square.and.arrow.up")

        /// composer — opens the photo library picker.
        static let attach = Image(systemName: "photo.badge.plus")

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

        /// leading glyph on an assistant-sent file attachment row.
        static let file = Image(systemName: "doc")

        /// fills an assistant-sent image tile whose load failed or whose signed URL expired.
        static let imageUnavailable = Image(systemName: "photo")

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
    /// caller substitutes the default palette instead of a half-applied theme. All-or-nothing is
    /// intentional for the core fields — optional chrome (borders, header button fill) is lenient.
    init?(_ theme: ChatConfig.Theme) {

        guard
            let accent = Color(css: theme.brand.primaryColor),
            let primaryText = Color(css: theme.messages.assistant.textColor),
            let userBubble = Color(css: theme.messages.user.backgroundColor),
            let userBubbleText = Color(css: theme.messages.user.textColor),
            let botSurface = Color(css: theme.messages.assistant.backgroundColor),
            let background = Color(css: theme.surface.backgroundColor),
            let secondaryText = Color(css: theme.surface.mutedTextColor),
            let discountPrice = Color(css: theme.productCard.discountPriceColor),
            let inputText = Color(css: theme.input.textColor),
            let inputPlaceholder = Color(css: theme.input.placeholderColor),
            let toolbarIcon = Color(css: theme.header.button.iconColor)
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
        self.inputBackground = theme.input.backgroundColor.flatMap(Color.init(css:))
        self.sendIcon = theme.input.sendButton.iconColor.flatMap(Color.init(css:))
        self.botSurfaceBorder = theme.messages.assistant.borderColor.flatMap(Color.init(css:))
        self.userBubbleBorder = theme.messages.user.borderColor.flatMap(Color.init(css:))
        self.inputBorder = theme.input.borderColor.flatMap(Color.init(css:))
        self.headerButtonBackground = theme.header.button.backgroundColor.flatMap(Color.init(css:))
        self.thinkingBorderGradient = theme.messages.assistant.thinkingBorderGradient.compactMap(Color.init(css:))
        self.productButtonBackground = theme.productCard.button.flatMap { Color(css: $0.backgroundColor) }
        self.productButtonBold = theme.productCard.button?.bold ?? true

        // Not yet wire-driven — borrow the SDK constants until the config carries them.

        // Notice/error bar fill; also the checkbox error state.
        self.errorBackground = Self.default.errorBackground
        // Notice/error bar icon + text.
        self.errorForeground = Self.default.errorForeground
        // Light foreground on filled action buttons (send, retry, delete-confirm). Reuse candidate: userBubbleText.
        self.accentForeground = Self.default.accentForeground
        // Destructive actions — delete button and the checkbox.
        self.destructive = Self.default.destructive
        // Neutral outline for secondary-button borders.
        self.outline = Self.default.outline
    }
}
