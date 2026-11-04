//
//  LoadEarlierButton.swift
//  AIConversation
//

import SwiftUI

/// Sits above the conversation while older turns remain, or while the first page hasn't loaded.
/// Older turns load when the visitor asks: a list can't hold its place across a prepend that lands
/// mid-scroll, and after a tap ``OlderTurnsAnchor`` brings the reader back to where they were.
struct LoadEarlierButton: View {

    let action: () async -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            guard !self.isLoading else { return }
            self.isLoading = true
            Task {
                await self.action()
                self.isLoading = false
            }
        } label: {
            AccentCapsuleLabel(title: L10n.historyLoadEarlier.string, isBusy: self.isLoading)
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .disabled(self.isLoading)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L10n.historyLoadEarlier.string)
        .accessibilityIdentifier("conversation.loadEarlier")
    }
}
