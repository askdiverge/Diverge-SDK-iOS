//
//  ThinkingBorderEffect.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-07.
//

import SwiftUI

/// An `AngularGradient` at an arbitrary rotation.
struct RotatingGradient: ShapeStyle {

    var angle: Double
    var colors: [Color]

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        // Repeat the first stop so the sweep closes without a seam.
        AngularGradient(
            colors: self.colors + self.colors.prefix(1),
            center: .center,
            angle: .degrees(self.angle)
        )
    }
}

/// Overlays the bubble with a `RotatingGradient` border that travels around the edge while a reply
/// is in flight — the "thinking" indicator. `shape` should match the bubble so the ring lands 1:1.
/// Static under Reduce Motion, no-op when the gradient palette is unset.
struct ThinkingBorderEffect<S: InsettableShape>: ViewModifier {

    @Environment(\.appearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let shape: S

    /// Seconds for one full revolution.
    private let period: TimeInterval = 2

    private var isVisible: Bool {
        self.isActive && !self.appearance.theme.thinkingBorderGradient.isEmpty
    }

    func body(content: Content) -> some View {
        content.overlay {
            Group {
                if self.isVisible {
                    self.sweep.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: self.isVisible)
        }
    }

    @ViewBuilder
    private var sweep: some View {
        if self.reduceMotion {
            self.border(angle: 0)
        } else {
            TimelineView(.animation) { context in
                self.border(angle: self.angle(at: context.date))
            }
        }
    }

    private func border(angle: Double) -> some View {
        self.shape
            .strokeBorder(
                RotatingGradient(angle: angle, colors: self.appearance.theme.thinkingBorderGradient),
                lineWidth: 1
            )
    }

    private func angle(at date: Date) -> Double {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: self.period)
        return elapsed / self.period * 360
    }
}
