//
//  IconButton.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-28.
//

import SwiftUI

/// A circular icon button — themed fill, hairline border, and a centered glyph.
struct IconButton: View {

    @Environment(\.appearance) private var appearance

    let icon: Image
    let action: () -> Void

    private var diameter: CGFloat {
        self.appearance.spacing.units(12)
    }

    var body: some View {
        Button(action: self.action) {
            self.icon
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.appearance.theme.primaryText)
                .frame(width: self.diameter, height: self.diameter)
                .background {
                    Circle()
                        .fill(self.appearance.theme.background)
                        .stroke(self.appearance.theme.botSurfaceBorder ?? .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
