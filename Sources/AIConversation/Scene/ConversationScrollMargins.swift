import SwiftUI

/// Space reserved under the last turn so `scrollTo(.bottom)` clears the overlaid composer.
///
/// The input is a `safeAreaInset` *outside* `NavigationStack` (in-stack insets collapse on some
/// sheet hosts). The conversation `List` then reports `contentInsets.bottom == 0`, and scrolling
/// the last turn to `.bottom` — including the scroll that runs when the field is focused — lands
/// that row under the bar. A trailing clearance row is real content, so `scrollTo` accounts for it.
enum ConversationComposerClearance {
    static let id = UUID(uuidString: "C0C0C0C0-0FF0-4000-8000-C0C0C0C00001")!

    static func height(composerHeight: CGFloat, spacing: ChatAppearance.Spacing) -> CGFloat {
        let fallback = spacing.units(24)
        let gap = spacing.units(2)
        return (composerHeight > 0 ? composerHeight : fallback) + gap
    }
}

struct ConversationComposerClearanceRow: View {
    let composerHeight: CGFloat
    @Environment(\.appearance) private var appearance

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: ConversationComposerClearance.height(
                composerHeight: self.composerHeight,
                spacing: self.appearance.spacing
            ))
            .id(ConversationComposerClearance.id)
            .accessibilityHidden(true)
    }
}

extension View {
    func measuringComposerHeight(_ height: Binding<CGFloat>) -> some View {
        self.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
            if abs(height.wrappedValue - measured) > 0.5 {
                height.wrappedValue = measured
            }
        }
    }
}
