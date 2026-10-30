//
//  ImageFailureView.swift
//  AIConversation
//

import SwiftUI

/// Fills a product or table image that failed to load, so the slot doesn't read as blank. The
/// card's own text carries the content, so VoiceOver skips it.
struct ImageFailureView: View {

    @Environment(\.appearance) private var appearance

    var body: some View {
        ChatAppearance.Symbol.imageUnavailable
            .font(.system(size: 20))
            .foregroundStyle(self.appearance.theme.primaryText.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
