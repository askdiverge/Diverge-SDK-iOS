//
//  OutlinedChipFlow.swift
//  AIConversation
//

import SwiftUI

/// Wrapping outlined capsule chips — shared by start prompts and in-conversation quick replies.
/// Identity is the chip index so duplicate labels stay distinct. `accessibilityPrefix` is the
/// identifier stem (`startPrompt` / `quickReply`).
struct OutlinedChipFlow: View {

    @Environment(\.appearance) private var appearance
    /// `.plain` buttons do not dim on their own and the chip paints an explicit accent, so a
    /// `.disabled(...)` chip (streaming) would look identical to a live one without this.
    @Environment(\.isEnabled) private var isEnabled

    /// Opacity applied to the whole flow while disabled.
    static let disabledOpacity: Double = 0.45

    let labels: [String]
    let accessibilityPrefix: String
    var accessibilityHint: String = L10n.startPromptSendHint.string
    let onSelect: (String) -> Void

    var body: some View {
        ChipFlowLayout(spacing: self.appearance.spacing.units(2)) {
            ForEach(Array(self.labels.enumerated()), id: \.offset) { index, label in
                Button {
                    self.onSelect(label)
                } label: {
                    Text(label)
                        .font(self.appearance.font(size: 14, weight: .semibold))
                        .foregroundStyle(self.appearance.theme.accent)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, self.appearance.spacing.units(3))
                        .padding(.vertical, self.appearance.spacing.units(2))
                        .background(self.appearance.theme.background, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(self.appearance.theme.accent.opacity(0.35), lineWidth: 1)
                        }
                        .minimumTouchTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityHint(self.accessibilityHint)
                .accessibilityIdentifier("\(self.accessibilityPrefix).\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(self.isEnabled ? 1 : Self.disabledOpacity)
    }
}

/// Simple wrap layout for chip rows — avoids a LazyVGrid of fixed columns that
/// would stretch short labels into unused columns. A chip wider than the container
/// is proposed at `maxWidth` so its text wraps instead of overflowing.
private struct ChipFlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        self.arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = self.arrange(proposal: proposal, subviews: subviews)
        for (index, item) in result.placements.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(width: item.width, height: item.height)
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, placements: [(origin: CGPoint, width: CGFloat, height: CGFloat)]) {
        let maxWidth = proposal.width ?? .infinity
        var placements: [(origin: CGPoint, width: CGFloat, height: CGFloat)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for subview in subviews {
            let unconstrained = subview.sizeThatFits(.unspecified)
            let chipWidth = maxWidth.isFinite ? min(unconstrained.width, maxWidth) : unconstrained.width
            let size = subview.sizeThatFits(ProposedViewSize(width: chipWidth, height: nil))
            let placedWidth = maxWidth.isFinite ? min(size.width, maxWidth) : size.width
            if x > 0, x + placedWidth > maxWidth {
                x = 0
                y += rowHeight + self.spacing
                rowHeight = 0
            }
            placements.append((CGPoint(x: x, y: y), placedWidth, size.height))
            rowHeight = max(rowHeight, size.height)
            x += placedWidth + self.spacing
            width = max(width, x - self.spacing)
        }

        return (CGSize(width: width, height: y + rowHeight), placements)
    }
}
