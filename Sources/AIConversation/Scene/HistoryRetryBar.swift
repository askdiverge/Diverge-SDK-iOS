//
//  HistoryRetryBar.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// The top-edge strip shown where the loading spinner was when an older-history page failed to
/// load: the reason and a retry, right where the reader is looking rather than as a passing notice.
struct HistoryRetryBar: View {

    @Environment(\.appearance) private var appearance

    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: self.appearance.spacing.units(3)) {
            Text(L10n.historyLoadFailed)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.errorForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: self.onRetry) {
                AccentCapsuleLabel(title: L10n.errorRetry.string, symbol: ChatAppearance.Symbol.retry)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, self.appearance.spacing.units(4))
        .padding(.trailing, self.appearance.spacing.units(2))
        .padding(.vertical, self.appearance.spacing.units(1))
        .background(self.appearance.theme.errorBackground, in: Capsule())
        .padding(.horizontal, self.appearance.spacing.units(4))
        .padding(.top, self.appearance.spacing.units(3))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.retry")
    }
}
