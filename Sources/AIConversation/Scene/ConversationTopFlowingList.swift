//
//  ConversationTopFlowingList.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-19.
//

import SwiftUI
import AIConversationEngine

/// Lifts each new user turn to the top and lets the bot answer flow into a buffer beneath it.
struct ConversationTopFlowingList<Content: View, Header: View, Footer: View>: View {

    /// A reference held in `@State` for a stable identity, whose writes don't invalidate the view.
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    @Environment(\.appearance) private var appearance

    let snapshot: ConversationSnapshot
    let isInputFocused: Bool
    /// Measured height of the overlaid composer; a trailing clearance row keeps the last turn above it.
    let composerClearance: CGFloat
    /// Loads the next older page when the reader scrolls near the top and reports how it went; the
    /// list keeps the reader in place when turns land above them and offers an inline retry when
    /// the load failed. See ``HistoryPagination``.
    /// A prepend only touches `.first` ids, so the exchange / buffer / reclaim machinery — which
    /// keys off `.last` — is undisturbed.
    let onLoadOlder: () async -> HistoryLoadOutcome

    @ViewBuilder let content: (Identified<ConversationSnapshot.Turn>) -> Content
    @ViewBuilder let header: () -> Header
    @ViewBuilder let footer: () -> Footer
    /// When false the footer is not inserted as a `List` row, so hiding chips does not leave
    /// `listRowSpacing` from an `EmptyView`.
    let showsFooter: Bool

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
    @State private var history = HistoryPaginator()

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
                .onChange(of: self.snapshot.lastSentUserTurnID) { _, userID in self.arm(userID, proxy: proxy) }
                .onChange(of: self.snapshot.lastUserTurnID) { _, _ in
                    if self.exchange != nil, !self.isArmed {
                        self.retire(proxy)
                    }
                }
                .onChange(of: self.snapshot.lastBotTurnID) { self.answerArrived(proxy) }
                .onChange(of: self.isInputFocused) { _, focused in if focused { self.scrollToNewest(proxy, animated: true) } }
                .onChange(of: self.composerClearance) { _, height in
                    if height > 0, self.isInputFocused || !self.isScrolledAway {
                        self.scrollToNewest(proxy, animated: true)
                    }
                }
        }
    }
}

// MARK: - The live exchange

private extension ConversationTopFlowingList {

    struct Exchange {
        let userID: UUID
        /// Measured heights of the turns from the lifted user turn down, keyed by id so a turn that has just
        /// arrived reads as unmeasured rather than inheriting a previous turn's height.
        var heights: [UUID: CGFloat] = [:]
    }

    /// The turns the exchange spans — the lifted user turn and everything beneath it — or empty when nothing
    /// is armed or the user turn has left the snapshot. Any number of turns may follow the user turn (one
    /// streamed answer today; system turns too), so the buffer sizes against all of
    /// them rather than a single "the answer".
    var exchangeTurns: ArraySlice<Identified<ConversationSnapshot.Turn>> {
        guard
            let exchange,
            let index = self.snapshot.turns.lastIndex(where: { $0.id == exchange.userID })
        else { return [] }
        return self.snapshot.turns[index...]
    }

    /// Whether the armed exchange's user turn is still present in the snapshot.
    var isArmed: Bool { !self.exchangeTurns.isEmpty }

    /// The buffer height that makes the exchange fill exactly one screen: the viewport minus the height the
    /// exchange already uses (every turn from the lifted user turn down, plus the row gap under each).
    ///
    /// A just-arrived turn hasn't been measured yet, so it counts as 0 — the buffer comes out a little too
    /// tall and settles once the turn measures. Erring tall keeps the user turn up top, erring short would
    /// let it spring back down.
    var reserve: CGFloat {
        guard let exchange else { return 0 }
        let turns = self.exchangeTurns
        guard !turns.isEmpty else { return 0 }
        let occupied = turns.reduce(CGFloat(turns.count) * self.rowSpacing) { $0 + (exchange.heights[$1.id] ?? 0) }
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
                        .historyRow(turn.id, in: self.history)
                        .id(turn.id)
                }

                if self.showsFooter {
                    self.footer()
                }

                ConversationComposerClearanceRow(composerHeight: self.composerClearance)

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
        // Paint the theme behind clear rows — otherwise a light palette in a dark
        // environment (unconfigured `dark_theme`) leaves system chrome showing through.
        .background(self.appearance.theme.background)
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
        .modifier(HistoryPagination(
            paginator: self.history,
            snapshot: self.snapshot,
            proxy: proxy,
            scrollTask: self.scrollTask,
            onLoadOlder: self.onLoadOlder
        ))
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
        case .system: .top
        case .user: .topTrailing
        }
    }
}

// MARK: - Reactions

private extension ConversationTopFlowingList {

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
    /// nothing is armed or the reader has taken over. The last user and last bot turn can both change in the
    /// same snapshot (a failed send drops both), so this checks `isArmed` rather than leaning on the order the
    /// two handlers run in.
    func answerArrived(_ proxy: ScrollViewProxy) {
        guard let exchange, self.isArmed, self.reclaimed == 0, !self.isUserScrolling.value else { return }
        self.pinToTop(exchange.userID, proxy: proxy)
    }

    /// Records a turn's height only while it belongs to the exchange — rows outside it are laid out
    /// constantly as the reader scrolls, and their heights play no part in the buffer.
    func measure(_ turn: Identified<ConversationSnapshot.Turn>, height: CGFloat) {
        guard
            self.exchange?.heights[turn.id] != height,
            self.exchangeTurns.contains(where: { $0.id == turn.id })
        else { return }
        self.exchange?.heights[turn.id] = height
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
        guard self.snapshot.turns.last != nil else { return }
        self.scroll(to: ConversationComposerClearance.id, anchor: .bottom, animated: animated, proxy: proxy)
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
        lhs.snapshot == rhs.snapshot
            && lhs.isInputFocused == rhs.isInputFocused
            && lhs.composerClearance == rhs.composerClearance
            && lhs.showsFooter == rhs.showsFooter
    }
}
