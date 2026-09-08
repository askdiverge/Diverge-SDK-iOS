//
//  MessageImageView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Renders an image part in either pane — an assistant / agent attachment, or the visitor's own
/// upload (this session's echo or history). Tapping opens the full-resolution `url` when it is
/// http(s); inline `data:` uploads render but are not tappable.
///
/// Signed attachment URLs expire (the API mints them with a short TTL), so the tile has two
/// unavailable states that share one look: the load failed, or `urlExpiresAt` has passed. In
/// either the tap is disabled and VoiceOver hears "unavailable" instead of the open hint.
///
/// The tile deliberately keeps `botSurface` / `secondaryText` in the user pane too: it is a
/// media frame, not a speech bubble, and one treatment keeps the two panes visually paired
/// (matches the web widget, which frames uploads identically on both sides).
struct MessageImageView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let image: MessageImage

    @State private var loadFailed = false
    @State private var expired = false

    /// `isExpired()` covers the first render before the watcher runs; `expired` covers the TTL
    /// passing while the tile is on screen.
    private var isAvailable: Bool {
        !self.loadFailed && !self.expired && !self.image.isExpired()
    }

    /// `openURL` only handles http(s). Inline `data:` URLs (visitor uploads in normal chat)
    /// still render; tapping them would be a no-op, so the tile is not a control at all.
    private var canOpen: Bool {
        Self.canOpen(self.image.url)
    }

    private var isTappable: Bool {
        self.isAvailable && self.canOpen
    }

    var body: some View {
        Group {
            if self.canOpen {
                // `.disabled` (not hit-testing) so an unavailable signed URL reads and looks
                // disabled — the tile already shows the unavailable state.
                Button {
                    self.openURL(self.image.url)
                } label: {
                    self.content
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .disabled(!self.isAvailable)
                .accessibilityHint(Self.accessibilityHint(isAvailable: self.isTappable))
            } else {
                // A plain image, not a dimmed button: the visitor's own upload is not "unavailable",
                // it simply has nowhere to open to.
                self.content
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
            }
        }
        .watchExpiry(self.image.urlExpiry, isExpired: self.$expired)
        .accessibilityLabel(Self.accessibilityLabel(for: self.image, isAvailable: self.isAvailable))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            self.tile
                .aspectRatio(4.0 / 3.0, contentMode: .fit)

            if let caption = self.image.caption {
                Text(caption)
                    .font(self.appearance.font(size: 12))
                    .foregroundStyle(self.appearance.theme.secondaryText)
            }
        }
    }

    /// An expired URL is not worth a request — show the unavailable state straight away.
    @ViewBuilder
    private var tile: some View {
        if self.expired || self.image.isExpired() {
            self.unavailable
                .background(self.appearance.theme.botSurface)
        } else {
            ClippedRemoteImage(url: self.image.thumbnailUrl ?? self.image.url) {
                self.unavailable
                    .onAppear { self.loadFailed = true }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: self.appearance.spacing.units(2)) {
            ChatAppearance.Symbol.imageUnavailable
                .font(.system(size: 28))
            Text(L10n.mediaUnavailable.string)
                .font(self.appearance.font(size: 12))
        }
        .foregroundStyle(self.appearance.theme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Accessibility contract

extension MessageImageView {

    /// VoiceOver label: the caption when present, otherwise a generic image label; an
    /// unavailable tile appends the unavailable copy so the disabled button explains itself.
    static func accessibilityLabel(for image: MessageImage, isAvailable: Bool) -> String {
        let subject: String
        if let caption = image.caption, !caption.isEmpty {
            subject = caption
        } else {
            subject = L10n.mediaImageLabel.string
        }
        return isAvailable ? subject : "\(subject). \(L10n.mediaUnavailable.string)"
    }

    /// The open hint only while activating the tile does something.
    static func accessibilityHint(isAvailable: Bool) -> String {
        isAvailable ? L10n.mediaOpenHint.string : ""
    }

    /// True when `openURL` can act on the scheme (http / https).
    static func canOpen(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
