//
//  ChatBannerChrome.swift
//  AIConversation
//

import SwiftUI

/// Fill / text colours for an in-chat banner. Unparseable hex falls back the
/// same way the web widget does (`themeColor` / `#ffffff`).
enum ChatBannerChrome {

    /// Card fill — valid CSS hex, otherwise the chatbot accent.
    static func fill(hex: String?, accent: Color) -> Color {
        hex.flatMap(Color.init(css:)) ?? accent
    }

    /// Body / CTA / dismiss glyph — valid CSS hex, otherwise white.
    static func foreground(hex: String?) -> Color {
        hex.flatMap(Color.init(css:)) ?? .white
    }
}
