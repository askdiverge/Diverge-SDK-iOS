//
//  WaveRenderer.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-06.
//

import SwiftUI

/// Bobs each glyph along a sine wave — drives the pre-delta thinking placeholder's dots.
/// `time` is supplied per frame by `WaveEffect`'s clock.
struct WaveRenderer: TextRenderer {

    var time: TimeInterval

    var animatableData: TimeInterval {
        get { self.time }
        set { self.time = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // layout → lines → runs → glyphs flatten all the way so each character
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }

        for (index, glyph) in glyphs.enumerated() {
            var glyphContext = context
            glyphContext.translateBy(x: 0, y: sin(self.time + Double(index) * 0.6) * -5)
            glyphContext.draw(glyph)
        }
    }
}

/// Bobs a view's glyphs on a looping sine wave — the loop lives as long as the view.
/// Static under Reduce Motion.
struct WaveEffect: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one full cycle of the wave.
    private let period: TimeInterval = 1.2

    func body(content: Content) -> some View {
        if self.reduceMotion {
            content
        } else {
            TimelineView(.animation) { context in
                content.textRenderer(WaveRenderer(time: self.phase(at: context.date)))
            }
        }
    }

    private func phase(at date: Date) -> TimeInterval {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: self.period)
        return elapsed / self.period * .pi * 2
    }
}
