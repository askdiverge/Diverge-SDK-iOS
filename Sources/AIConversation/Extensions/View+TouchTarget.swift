//
//  View+TouchTarget.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-24.
//

import SwiftUI

extension View {

    /// Guarantees a minimum touch target of the appearance's `minTouchTarget` by growing the frame
    /// to at least that size and making the whole area hittable. `alignment` places the visible
    /// content within it, so an edge control stays flush while the target grows inward into slack.
    func minimumTouchTarget(alignment: Alignment = .center) -> some View {
        self.modifier(MinimumTouchTarget(alignment: alignment))
    }
}

private struct MinimumTouchTarget: ViewModifier {

    @Environment(\.appearance) private var appearance

    let alignment: Alignment

    func body(content: Content) -> some View {
        content
            .frame(
                minWidth: self.appearance.spacing.units(11),
                minHeight: self.appearance.spacing.units(11),
                alignment: self.alignment
            )
            .contentShape(Rectangle())
    }
}
