//
//  AvatarImage.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-26.
//

import SwiftUI

/// Fronts content with the chat avatar on the given edge.
struct AvatarImage: ViewModifier {

    @Environment(\.appearance) private var appearance

    let image: Image?
    let edge: HorizontalEdge

    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: self.appearance.spacing.units(2)) {
            switch self.edge {
            case .leading:
                self.avatar
                content

            case .trailing:
                content
                self.avatar
            }
        }
    }

    private var avatar: some View {
        let badge = self.appearance.spacing.units(8)
        return Group {
            if let image = self.image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: badge * 0.5, height: badge * 0.5)
            } else {
                self.appearance.theme.botSurface
            }
        }
        .frame(width: badge, height: badge)
        .background(self.appearance.theme.botSurface)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(self.appearance.theme.botSurfaceBorder ?? .clear, lineWidth: 1))
    }
}
