//
//  ChatBannerCard.swift
//  AIConversation
//

import SwiftUI
import AIConversationEngine

/// Single promo strip — colours from the banner with theme fallbacks matching the web widget
/// (`themeColor` / `#ffffff`). CTA opens via the environment `openURL` (host `onOpenLink`).
struct ChatBannerCard: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let banner: ChatBanner
    let onDismiss: () -> Void

    var body: some View {
        let fill = ChatBannerChrome.fill(
            hex: self.banner.backgroundColor,
            accent: self.appearance.theme.accent
        )
        let foreground = ChatBannerChrome.foreground(hex: self.banner.textColor)

        HStack(alignment: .center, spacing: self.appearance.spacing.units(2)) {
            Text(self.banner.message)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)

            if self.banner.showsCTA,
               let label = self.banner.trimmedCTALabel,
               let url = self.banner.sanitizedCTAURL {
                self.ctaButton(label: label, url: url, foreground: foreground)
            }
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.vertical, self.appearance.spacing.units(2))
        .padding(.trailing, self.banner.dismissible ? 44 : 0)
        .frame(maxWidth: .infinity)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("banner.\(self.banner.id)")
        .overlay(alignment: .topTrailing) {
            if self.banner.dismissible {
                Button(action: self.onDismiss) {
                    ChatAppearance.Symbol.close
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.bannerDismiss.string)
                .accessibilityIdentifier("banner.dismiss.\(self.banner.id)")
            }
        }
    }

    @ViewBuilder
    private func ctaButton(label: String, url: URL, foreground: Color) -> some View {
        let isButton = self.banner.ctaStyle == .button
        Button {
            self.openURL(url)
        } label: {
            Text(label)
                .font(self.appearance.font(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .underline(!isButton)
                .padding(.horizontal, isButton ? self.appearance.spacing.units(2) : 0)
                .padding(.vertical, isButton ? self.appearance.spacing.units(1) : 0)
                .background {
                    if isButton {
                        Capsule()
                            .strokeBorder(foreground, lineWidth: 1)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                }
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(L10n.bannerCTA.string)
        .accessibilityIdentifier("banner.cta.\(self.banner.id)")
    }
}
