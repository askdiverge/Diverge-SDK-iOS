//
//  HeaderToolbarIcon.swift
//  AIConversation
//

import SwiftUI

/// Header toolbar glyph — paints `theme.toolbarIcon` and an optional `headerButtonBackground` fill.
struct HeaderToolbarIcon: View {

    @Environment(\.appearance) private var appearance

    let symbol: Image

    var body: some View {
        self.symbol
            .foregroundStyle(self.appearance.theme.toolbarIcon)
            .padding(self.appearance.spacing.units(2))
            .background {
                if let fill = self.appearance.theme.headerButtonBackground {
                    Circle().fill(fill)
                }
            }
    }
}
