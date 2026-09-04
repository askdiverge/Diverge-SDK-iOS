//
//  TypewriterRenderer.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-07.
//

import SwiftUI

/// Reveals glyphs up to `visibleCount`, fading the leading one in by its fractional part.
/// `visibleCount` is interpolated by `withAnimation` (`TextRenderer` refines `Animatable`).
struct TypewriterRenderer: TextRenderer {

    var visibleCount: Double

    var animatableData: Double {
        get { self.visibleCount }
        set { self.visibleCount = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }

        for (index, glyph) in glyphs.enumerated() {
            let edge = self.visibleCount - Double(index)
            guard edge > 0 else { break }
            var glyphContext = context
            glyphContext.opacity = min(edge, 1)
            glyphContext.draw(glyph)
        }
    }
}

/// Types a bot bubble's text in as it streams. `revealed` persists across deltas — each new
/// snapshot animates it from where it is up to the new length, so already-shown text stays put
/// (replaced in place, never re-typed) and only the tail types. Static under Reduce Motion.
struct TypewriterEffect: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: AttributedString
    let isActive: Bool

    @State private var revealed: Double = 0

    func body(content: Content) -> some View {
        if self.isActive, !self.reduceMotion {
            content
                .textRenderer(TypewriterRenderer(visibleCount: self.revealed))
                .onChange(of: self.text, initial: true) { _, new in
                    let target = Double(new.characters.count)
                    withAnimation(.linear(duration: max(target - self.revealed, 0) * 0.01)) {
                        self.revealed = target
                    }
                }
        } else {
            content
        }
    }
}
