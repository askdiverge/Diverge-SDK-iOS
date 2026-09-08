//
//  ChatBannerStrip.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Sticky stack of in-chat promo banners under the nav / above the conversation list.
struct ChatBannerStrip: View {

    @Environment(\.appearance) private var appearance

    let banners: [ChatBanner]
    let onDismiss: (ChatBanner) -> Void

    var body: some View {
        VStack(spacing: self.appearance.spacing.units(2)) {
            ForEach(self.banners) { banner in
                ChatBannerCard(banner: banner) {
                    self.onDismiss(banner)
                }
            }
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.bottom, self.appearance.spacing.units(2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banner.strip")
    }
}
