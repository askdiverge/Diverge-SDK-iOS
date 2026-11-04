//
//  MessageFileView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Renders an agent- or assistant-sent file part as a tappable row. A tap asks `resolveURL` for
/// the link to open, a freshly signed one when the stored link is temporary, and hands it to
/// `openURL`, which the host can route through `onOpenLink`. One tap resolves at a time, and the
/// row going away cancels it, so nothing opens after the chat closes. A file whose link can't be
/// opened, or whose expired link can't be re-signed, shows the unavailable copy.
struct MessageFileView: View {

    @Environment(\.appearance) private var appearance
    @Environment(\.openURL) private var openURL

    let file: MessageFile
    let resolveURL: @MainActor (MessageFile) async -> URL?

    /// The tap resolving the link, while it does.
    @State private var opening: Task<Void, Never>?
    /// Set when the stored link expired and the log couldn't re-sign it.
    @State private var linkExpired = false

    var body: some View {
        let canOpen = Self.canOpen(self.file, linkExpired: self.linkExpired)
        Button {
            guard self.opening == nil else { return }
            self.opening = Task {
                let url = await self.resolveURL(self.file)
                self.opening = nil
                guard !Task.isCancelled else { return }
                if let url {
                    self.openURL(url)
                } else {
                    self.linkExpired = true
                }
            }
        } label: {
            HStack(spacing: self.appearance.spacing.units(3)) {
                ChatAppearance.Symbol.file
                    .font(self.appearance.font(size: 20))
                    .foregroundStyle(self.appearance.theme.primaryText)

                VStack(alignment: .leading, spacing: self.appearance.spacing.units(1)) {
                    Text(self.file.filename)
                        .font(self.appearance.font(size: 13, weight: .bold))
                        .foregroundStyle(self.appearance.theme.primaryText)
                        .lineLimit(2)

                    if let detail = Self.detail(for: self.file, linkExpired: self.linkExpired) {
                        Text(detail)
                            .font(self.appearance.font(size: 12))
                            .foregroundStyle(self.appearance.theme.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                if canOpen {
                    ChatAppearance.Symbol.externalLink
                        .font(self.appearance.font(size: 14))
                        .foregroundStyle(self.appearance.theme.secondaryText)
                }
            }
            .padding(self.appearance.spacing.units(3))
            .background(self.appearance.theme.botSurface)
            .border(self.appearance.theme.botSurfaceBorder ?? .clear, width: 1)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .minimumTouchTarget(alignment: .leading)
        .disabled(!canOpen)
        .accessibilityLabel(Self.accessibilityLabel(for: self.file, linkExpired: self.linkExpired))
        .accessibilityHint(canOpen ? L10n.mediaOpenHint.string : "")
        .onDisappear {
            self.opening?.cancel()
            self.opening = nil
        }
    }
}

// MARK: - Accessibility contract

extension MessageFileView {

    /// Whether `openURL` can open the file's link: http(s) only, and not once `linkExpired` says
    /// an expired link couldn't be re-signed. Inline `data:` links can't be opened from here.
    static func canOpen(_ file: MessageFile, linkExpired: Bool) -> Bool {
        let scheme = file.url.scheme?.lowercased()
        return !linkExpired && (scheme == "http" || scheme == "https")
    }

    /// Secondary line: the formatted size of a file that can be opened, the unavailable copy for
    /// one that can't. Nil when the size is unknown.
    static func detail(for file: MessageFile, linkExpired: Bool) -> String? {
        guard Self.canOpen(file, linkExpired: linkExpired) else { return L10n.mediaUnavailable.string }
        return file.sizeBytes.map { Int64($0).formatted(.byteCount(style: .file)) }
    }

    /// VoiceOver label: the filename, then the same detail the row shows — VoiceOver users hear
    /// the size or the unavailable state, not just the name.
    static func accessibilityLabel(for file: MessageFile, linkExpired: Bool) -> String {
        guard let detail = Self.detail(for: file, linkExpired: linkExpired) else { return file.filename }
        return "\(file.filename). \(detail)"
    }
}
