//
//  MessageFileView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Renders an assistant-sent file part as a tappable row. Tapping opens the download `url`.
/// Once the signed URL has passed `urlExpiresAt` the row is disabled and says so.
struct MessageFileView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let file: MessageFile

    @State private var expired = false

    /// `isExpired()` covers the first render before the watcher runs; `expired` covers the TTL
    /// passing while the row is on screen.
    private var isAvailable: Bool {
        !self.expired && !self.file.isExpired()
    }

    /// `openURL` only handles http(s). Inline `data:` URLs still show the row; tapping would
    /// be a no-op, so the button stays disabled and the external-link glyph is hidden.
    private var canOpen: Bool {
        MessageImageView.canOpen(self.file.url)
    }

    private var isTappable: Bool {
        self.isAvailable && self.canOpen
    }

    var body: some View {
        Button {
            self.openURL(self.file.url)
        } label: {
            HStack(spacing: self.appearance.spacing.units(3)) {
                ChatAppearance.Symbol.file
                    .font(.system(size: 20))
                    .foregroundStyle(self.appearance.theme.primaryText)

                VStack(alignment: .leading, spacing: self.appearance.spacing.units(1)) {
                    Text(self.file.filename)
                        .font(self.appearance.font(size: 13, weight: .bold))
                        .foregroundStyle(self.appearance.theme.primaryText)
                        .lineLimit(2)

                    if let detail = Self.detail(for: self.file, isAvailable: self.isAvailable) {
                        Text(detail)
                            .font(self.appearance.font(size: 12))
                            .foregroundStyle(self.appearance.theme.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                if self.isTappable {
                    ChatAppearance.Symbol.externalLink
                        .font(.system(size: 14))
                        .foregroundStyle(self.appearance.theme.secondaryText)
                }
            }
            .padding(self.appearance.spacing.units(3))
            .background(self.appearance.theme.botSurface)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .disabled(!self.isTappable)
        .watchExpiry(self.file.urlExpiry, isExpired: self.$expired)
        .accessibilityLabel(Self.accessibilityLabel(for: self.file, isAvailable: self.isAvailable))
        .accessibilityHint(self.isTappable ? L10n.mediaOpenHint.string : "")
    }
}

// MARK: - Accessibility contract

extension MessageFileView {

    /// Secondary line: the formatted size while the file can be opened, the unavailable copy once
    /// its signed URL has expired. Nil when there is nothing to say.
    static func detail(for file: MessageFile, isAvailable: Bool) -> String? {
        guard isAvailable else { return L10n.mediaUnavailable.string }
        return file.sizeBytes.map { Int64($0).formatted(.byteCount(style: .file)) }
    }

    /// VoiceOver label: the filename, then the same detail the row shows — VoiceOver users hear
    /// the size or the unavailable state, not just the name.
    static func accessibilityLabel(for file: MessageFile, isAvailable: Bool) -> String {
        guard let detail = Self.detail(for: file, isAvailable: isAvailable) else { return file.filename }
        return "\(file.filename). \(detail)"
    }
}
