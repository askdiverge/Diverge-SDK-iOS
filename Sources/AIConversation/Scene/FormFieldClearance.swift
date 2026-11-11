//
//  FormFieldClearance.swift
//  AIConversation
//

import SwiftUI

/// Room at the end of the conversation while a form field has the keyboard.
///
/// The composer sits above the keyboard, and the conversation scrolls only as far as its own end, so
/// the last fields of a form in the newest reply stay under the composer. This row, as tall as the
/// composer, gives the conversation room to scroll the focused field clear of it.
struct FormFieldClearance: View {

    @Environment(\.composerHeight) private var composerHeight

    /// Whether a form field has the keyboard.
    let isActive: Bool

    var body: some View {
        if self.isActive, self.composerHeight > 0 {
            Color.clear
                .frame(height: self.composerHeight)
                .accessibilityHidden(true)
        }
    }
}

extension EnvironmentValues {
    /// The height of the composer below the conversation; 0 before it is measured.
    var composerHeight: CGFloat {
        get { self[ComposerHeightKey.self] }
        set { self[ComposerHeightKey.self] = newValue }
    }
}

private struct ComposerHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
