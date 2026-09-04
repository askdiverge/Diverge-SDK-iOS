//
//  BootstrapErrorView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

/// The blocking full-screen state shown when the chat fails to load, with a retry.
struct BootstrapErrorView: View {

    @Environment(\.appearance) private var appearance

    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: self.appearance.spacing.units(12)) {
            self.message
            self.retryButton
        }
        .padding(.horizontal, self.appearance.spacing.units(4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(self.appearance.theme.background)
    }

    private var message: some View {
        VStack(spacing: self.appearance.spacing.units(6)) {
            ChatAppearance.Symbol.errorHero
                .font(.system(size: 34))
                .foregroundStyle(self.appearance.theme.primaryText)

            VStack(spacing: self.appearance.spacing.units(2)) {
                Text(L10n.errorTitle)
                    .font(self.appearance.font(size: 28, weight: .bold))

                Text(L10n.errorMessage)
                    .font(self.appearance.font(size: 15))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(self.appearance.theme.primaryText)
            .multilineTextAlignment(.center)
        }
    }

    private var retryButton: some View {
        Button(action: self.onRetry) {
            HStack(spacing: self.appearance.spacing.units(2)) {
                ChatAppearance.Symbol.retry
                    .font(.system(size: 16))

                Text(L10n.errorRetry)
                    .font(self.appearance.font(size: 13, weight: .bold))
            }
            .foregroundStyle(self.appearance.theme.accentForeground)
            .padding(self.appearance.spacing.units(2))
            .frame(maxWidth: .infinity, minHeight: self.appearance.spacing.units(12))
            .background(self.appearance.theme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
