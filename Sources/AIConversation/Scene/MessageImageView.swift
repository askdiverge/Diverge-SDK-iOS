//
//  MessageImageView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Renders an image part in either pane — an assistant / agent attachment, or the visitor's own
/// upload (this session's echo or history). Tapping an http(s) image asks `resolveURL` for the
/// full-resolution link, a freshly signed one when the stored link is temporary, and hands it to
/// `openURL`; inline `data:` uploads render but are not tappable.
///
/// Signed attachment URLs expire (the API mints them with a short TTL). The tile shows the
/// unavailable look when its image fails to load, which is how an expired link that isn't loaded
/// yet shows; an image already loaded stays when its link expires. VoiceOver hears "unavailable",
/// and the tap still opens a fresh link. One tap resolves at a time, and the tile going away
/// cancels it, so nothing opens after the chat closes. A tap that can't re-sign the link leaves it
/// for the next tap to try again.
///
/// The tile deliberately keeps `botSurface` / `secondaryText` in the user pane too: it is a
/// media frame, not a speech bubble, and one treatment keeps the two panes visually paired
/// (matches the web widget, which frames uploads identically on both sides).
struct MessageImageView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let image: MessageImage
    let resolveURL: @MainActor (MessageImage) async -> URL?

    @State private var loadFailed = false
    /// The tap resolving the link, while it does.
    @State private var opening: Task<Void, Never>?
    /// Set when the stored link expired and the last tap couldn't re-sign it.
    @State private var linkExpired = false

    private var isAvailable: Bool {
        !self.loadFailed
    }

    /// `openURL` only handles http(s). Inline `data:` URLs (visitor uploads in normal chat)
    /// still render; tapping them would be a no-op, so the tile is not a control at all.
    private var canOpen: Bool {
        Self.canOpen(self.image.url)
    }

    var body: some View {
        Group {
            if self.canOpen {
                Button {
                    guard self.opening == nil else { return }
                    self.opening = Task {
                        let url = await self.resolveURL(self.image)
                        self.opening = nil
                        guard !Task.isCancelled else { return }
                        self.linkExpired = url == nil
                        if let url {
                            self.openURL(url)
                        }
                    }
                } label: {
                    self.content
                }
                .buttonStyle(.plain)
                .contentShape(.rect)
                .accessibilityHint(Self.accessibilityHint(canOpen: !self.linkExpired))
                .onDisappear {
                    self.opening?.cancel()
                    self.opening = nil
                }
            } else {
                // A plain image, not a dimmed button: the visitor's own upload is not "unavailable",
                // it simply has nowhere to open to.
                self.content
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
            }
        }
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

    /// The image, or the unavailable look when it won't load. An expired link is still asked for:
    /// the loader may hold the image already.
    private var tile: some View {
        ClippedRemoteImage(url: self.image.thumbnailUrl ?? self.image.url) {
            self.unavailable
                .onAppear { self.loadFailed = true }
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
    static func accessibilityHint(canOpen: Bool) -> String {
        canOpen ? L10n.mediaOpenHint.string : ""
    }

    /// True when `openURL` can act on the scheme (http / https).
    static func canOpen(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
