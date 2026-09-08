//
//  RatingScaleView.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI

/// Five numbered 1–5 buttons matching the web widget's close-rating scale.
struct RatingScaleView: View {

    @Environment(\.appearance) private var appearance

    let isEnabled: Bool
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: self.appearance.spacing.units(2)) {
            ForEach(1...5, id: \.self) { score in
                Button {
                    self.onPick(score)
                } label: {
                    Text("\(score)")
                        .font(self.appearance.font(size: 17, weight: .bold))
                        .foregroundStyle(self.appearance.theme.accentForeground)
                        .frame(
                            minWidth: self.appearance.spacing.units(11),
                            minHeight: self.appearance.spacing.units(11)
                        )
                        .background(
                            ChatAppearance.Theme.ratingColor(for: score),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!self.isEnabled)
                .accessibilityLabel(Self.label(for: score))
                .accessibilityIdentifier("rating.score.\(score)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    static func label(for score: Int) -> String {
        switch score {
        case 1: L10n.ratingScore1.string
        case 2: L10n.ratingScore2.string
        case 3: L10n.ratingScore3.string
        case 4: L10n.ratingScore4.string
        default: L10n.ratingScore5.string
        }
    }
}
