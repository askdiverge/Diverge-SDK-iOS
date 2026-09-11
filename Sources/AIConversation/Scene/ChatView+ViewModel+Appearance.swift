//
//  ChatView+ViewModel+Appearance.swift
//  AIConversation
//

import SwiftUI

/// Color-scheme resolution: host preference × environment × the palettes `/config` supplied.
extension ChatView.ViewModel {

    /// Resolves the active color scheme from the host preference and the environment.
    func resolvedScheme(environment: ColorScheme) -> ColorScheme {
        switch self.appearancePreference {
        case .system: environment
        case .light: .light
        case .dark: .dark
        }
    }

    /// System chrome follows the **painted** palette, not the host lock alone.
    /// `nil` while `appearance` is unset (loading / failed) so the environment owns chrome.
    /// A cloned `dark_theme` paints light, so a `.dark` lock still returns `.light`.
    ///
    /// Under ``AIChat/Appearance/system`` with a distinct dark palette the painted scheme
    /// *is* the environment scheme, so this returns `nil`: `preferredColorScheme` writes
    /// back into the very environment the view reads, and a non-`nil` value here would pin
    /// the chat to whichever scheme it first rendered in and ignore a live system flip.
    func preferredColorScheme(for appearance: ChatAppearance?) -> ColorScheme? {
        guard let appearance else { return nil }
        if self.appearancePreference == .system, appearance.hasDistinctDarkPalette {
            return nil
        }
        return appearance.chromeColorScheme
    }
}
