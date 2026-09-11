//
//  CardGrid.swift
//  AIConversation
//

import SwiftUI

/// Two-column conversation card grid — shared by product and suggestion layouts.
/// Callers own per-cell buttons, accessibility, and card chrome; this only owns
/// the column metrics and spacing from ``ChatAppearance``.
struct CardGrid<Content: View>: View {

    @Environment(\.appearance) private var appearance

    let itemCount: Int
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: self.appearance.spacing.units(2)),
                GridItem(.flexible())
            ],
            alignment: .leading,
            spacing: self.appearance.spacing.units(3)
        ) {
            ForEach(0..<self.itemCount, id: \.self) { index in
                self.content(index)
            }
        }
    }
}
