//
//  ConversationTopFlowingList.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-19.
//

import SwiftUI
import AIConversationEngine

/// Lifts each new user turn to the top and lets the bot answer flow into a buffer beneath it.
struct ConversationTopFlowingList<Content: View, Header: View>: View {

    /// A reference held in `@State` for a stable identity, whose writes don't invalidate the view.
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @Environment(\.appearance) private var appearance

    let snapshot: ConversationSnapshot
    let isInputFocused: Bool
    let onLoadOlder: () async -> Void

    @ViewBuilder let content: (Identified<ConversationSnapshot.Turn>) -> Content
    @ViewBuilder let header: () -> Header

    /// The live user turn lifted on the last send and the bot answer flowing beneath it. `nil`
    /// before the first send - loaded history gets no buffer.
    @State private var exchange: Exchange?
    /// Largest (keyboard-down) visible viewport; the buffer is sized against it so it stays keyboard-independent.
    @State private var viewportHeight: CGFloat = 0
    /// How much of the buffer the reader has scrolled away (consumed).
    @State private var reclaimed: CGFloat = 0
    @State private var isScrolledAway = false
    @State private var isInitialLoad = true

    // Written from scroll callbacks, never read in `body` — boxed so their churn triggers no renders.
    @State private var isUserScrolling = Box(false)
    @State private var scrollTask = ScrollTaskBox()

    private var rowSpacing: CGFloat { self.appearance.spacing.units(11) }

    var body: some View {
        ScrollViewReader { proxy in
            self.conversation(proxy)
                .overlay(alignment: .bottom) { self.scrollToBottomButton(proxy) }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: self.snapshot, initial: true) {
                    // Open at the newest turn once, afterwards a send lifts to the top instead.
                    guard self.isInitialLoad else { return }
                    self.scrollToNewest(proxy)
                    self.isInitialLoad = false
                }
                .onChange(of: self.snapshot.user.last?.id) { _, userID in self.userTurnChanged(userID, proxy: proxy) }
                .onChange(of: self.snapshot.incoming.last?.id) { self.answerArrived(proxy) }
                .onChange(of: self.isInputFocused) { _, focused in if focused { self.scrollToNewest(proxy, animated: true) } }
        }
    }
}

// MARK: - The live exchange

private extension ConversationTopFlowingList {

    struct Exchange {
        let userID: UUID
        var userHeight: CGFloat = 0
        /// Keyed by id so a fresh answer reads as unmeasured rather than the previous answer's height.
        var bot: (id: UUID, height: CGFloat)?
    }

    /// Whether the armed exchange's user turn is still present in the snapshot.
    var isArmed: Bool {
        guard let exchange else { return false }
        return self.snapshot.user.contains { $0.id == exchange.userID }
    }

    /// The buffer height that makes the exchange fill exactly one screen: the viewport minus the height the
    /// exchange already uses (the user turn, the answer, and the row gaps between them).
    ///
    /// A just-arrived answer hasn't been measured yet, so it's treated as 0 — the buffer comes out a little
    /// too tall and settles once the answer measures. Erring tall keeps the user turn up top, erring short
    /// would let it spring back down.
    var reserve: CGFloat {
        guard let exchange, self.isArmed else { return 0 }
        let botTurnIsLast = self.snapshot.user.count <= self.snapshot.incoming.count
        var botHeight: CGFloat { exchange.bot.map { $0.id == self.snapshot.incoming.last?.id ? $0.height : 0 } ?? 0 }
        let occupied = botTurnIsLast
        ? exchange.userHeight + self.rowSpacing + botHeight + self.rowSpacing
        : exchange.userHeight + self.rowSpacing
        return max(0, self.viewportHeight - occupied)
    }
}

// MARK: - Layout

private extension ConversationTopFlowingList {

    func conversation(_ proxy: ScrollViewProxy) -> some View {
        List {
            Group {
                self.header()

                ForEach(self.snapshot.turns) { turn in
                    self.content(turn)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { self.measure(turn, height: $0) }
                        .frame(maxWidth: .infinity, alignment: self.alignment(turn.model))
                        .id(turn.id)
                }

                self.buffer
            }
            .listRowInsets(
                .init(
                    top: 0,
                    leading: self.appearance.spacing.units(4),
                    bottom: 0,
                    trailing: self.appearance.spacing.units(4)
                )
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
#if os(iOS)
        .listRowSpacing(self.rowSpacing)
#endif
        .onScrollGeometryChange(for: Bool.self) { self.isAway($0) } action: { _, away in
            if self.isScrolledAway != away { self.isScrolledAway = away }
        }
        .onScrollGeometryChange(for: CGFloat.self) { self.visibleViewport($0) } action: { _, height in
            if height > self.viewportHeight { self.viewportHeight = height }
        }
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { self.reclaim($0, $1) }
        .onScrollPhaseChange { _, phase, _ in
            self.isUserScrolling.value = phase == .interacting || phase == .decelerating
        }
    }

    /// The buffer below the exchange, a trailing row, separate from the answer, so a focus scroll lands the
    /// answer's content and this stays off-screen behind the keyboard. Omitted at 0 to add no phantom gap.
    @ViewBuilder
    var buffer: some View {
        let height = max(0, self.reserve - self.reclaimed)
        if height > 0 {
            Color.clear.frame(height: height)
        }
    }

    /// Jump-to-bottom control, surfaced once the reader has scrolled away. Wears the thinking border while a reply streams.
    func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        IconButton(icon: ChatAppearance.Symbol.scrollToBottom) {
            self.scrollToNewest(proxy, animated: true)
        }
        .modifier(ThinkingBorderEffect(isActive: self.snapshot.streamingTurnID != nil, shape: Circle()))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .padding(.bottom, self.appearance.spacing.units(2))
        .opacity(self.isScrolledAway && !self.isInputFocused ? 1 : 0)
        .allowsHitTesting(self.isScrolledAway && !self.isInputFocused)
        .animation(.easeInOut(duration: 0.2), value: self.isScrolledAway)
    }

    func alignment(_ turn: ConversationSnapshot.Turn) -> Alignment {
        switch turn {
        case .bot: .topLeading
        case .user: .topTrailing
        }
    }
}

// MARK: - Reactions

private extension ConversationTopFlowingList {

    /// The newest user turn changed: a turn that arrived arms an exchange, one that left retires the
    /// exchange it belonged to rather than arming the turn it uncovers.
    func userTurnChanged(_ userID: UUID?, proxy: ScrollViewProxy) {
        if self.exchange != nil, !self.isArmed {
            self.retire(proxy)
        } else {
            self.arm(userID, proxy: proxy)
        }
    }

    /// Drops the exchange and returns to the newest turn. The buffer belongs to an exchange in flight,
    /// so it collapses with the exchange rather than waiting to be reclaimed.
    func retire(_ proxy: ScrollViewProxy) {
        self.exchange = nil
        self.reclaimed = 0
        self.scrollToNewest(proxy, animated: true)
    }

    /// A send starts the exchange and brings the new user turn to the bottom edge. That scroll also realizes
    /// the buffer beneath it, so the lift in `answerArrived` has the reserve laid out to reach the top.
    func arm(_ userID: UUID?, proxy: ScrollViewProxy) {
        guard let userID else { return }
        self.exchange = Exchange(userID: userID)
        self.reclaimed = 0
        self.scrollToNewest(proxy)
    }

    /// The answer arriving relays out under the lift and can leave the user turn short, re-assert it, unless
    /// nothing is armed or the reader has taken over. Both panes can lose their last turn in the same
    /// snapshot, so this checks `isArmed` rather than leaning on the order the two handlers run in.
    func answerArrived(_ proxy: ScrollViewProxy) {
        guard let exchange, self.isArmed, self.reclaimed == 0, !self.isUserScrolling.value else { return }
        self.pinToTop(exchange.userID, proxy: proxy)
    }

    func measure(_ turn: Identified<ConversationSnapshot.Turn>, height: CGFloat) {
        if turn.id == self.exchange?.userID { self.exchange?.userHeight = height }
        if turn.id == self.snapshot.incoming.last?.id { self.exchange?.bot = (turn.id, height) }
    }

    /// Reclaim the buffer as the reader drags up or as the focus scroll travels, so the keyboard consumes
    /// the buffer with its motion. Offsets are clamped to the valid range so overscroll (bounce) counts as
    /// nothing. Stops once the buffer is gone.
    func reclaim(_ old: ScrollGeometry, _ new: ScrollGeometry) {
        guard self.isUserScrolling.value || self.isInputFocused, self.reclaimed < self.reserve else { return }
        let maxOffset = new.contentSize.height + new.contentInsets.bottom - new.containerSize.height
        let minOffset = -new.contentInsets.top
        let from = min(max(old.contentOffset.y, minOffset), maxOffset)
        let to = min(max(new.contentOffset.y, minOffset), maxOffset)
        if from > to { self.reclaimed += from - to }
    }

    /// Scrolled up beyond the resting bottom (which sits `contentInsets.bottom` past `contentSize`, since
    /// `visibleRect` spans the full container). Held false while the buffer is still reclaiming — content
    /// size lags the offset by a frame there, which would otherwise flash the button.
    func isAway(_ geometry: ScrollGeometry) -> Bool {
        guard self.reclaimed >= self.reserve else { return false }
        return geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY > self.appearance.spacing.units(4)
    }

    func visibleViewport(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
    }
}

// MARK: - Scrolling

private extension ConversationTopFlowingList {

    func scrollToNewest(_ proxy: ScrollViewProxy, animated: Bool = false) {
        self.scroll(to: self.snapshot.turns.last?.id, anchor: .bottom, animated: animated, proxy: proxy)
    }

    func pinToTop(_ id: UUID, proxy: ScrollViewProxy) {
        self.scroll(to: id, anchor: .top, animated: true, proxy: proxy)
    }

    /// Coalesces a burst of requests into one scroll, yielding once so a just-changed layout can commit before
    /// we target it — otherwise the target is out of range and the scroll springs back.
    func scroll(to id: UUID?, anchor: UnitPoint, animated: Bool, proxy: ScrollViewProxy) {
        guard let id else { return }
        self.scrollTask.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            if animated {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: anchor) }
            } else {
                proxy.scrollTo(id, anchor: anchor)
            }
        })
    }
}

// MARK: - Equatable

extension ConversationTopFlowingList: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.isInputFocused == rhs.isInputFocused
    }
}
