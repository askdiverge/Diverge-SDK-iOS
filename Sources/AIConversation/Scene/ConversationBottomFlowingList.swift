//
//  ConversationBottomFlowingList.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-08-19.
//

import SwiftUI
import AIConversationEngine

/// Lays out a conversation Leading/Trailing. Classic chat flow: new turns land at the bottom and the list
/// follows the newest turn (unless the reader has scrolled away).
struct ConversationBottomFlowingList<Content: View, Header: View, Footer: View>: View {

    @Environment(\.appearance) private var appearance

    let snapshot: ConversationSnapshot

    /// Whether the input holds focus. Gaining focus scrolls to the newest turn — selecting the field to
    /// reply shouldn't leave the reader up in history, and it pins the latest message above the keyboard.
    let isInputFocused: Bool

    /// Measured height of the overlaid composer; a trailing clearance row keeps the last turn above it.
    let composerClearance: CGFloat

    /// Loads the next older page when the reader scrolls near the top and reports how it went; the
    /// list keeps the reader in place when turns land above them and offers an inline retry when
    /// the load failed. See ``HistoryPagination``.
    let onLoadOlder: () async -> HistoryLoadOutcome

    @ViewBuilder let content: (Identified<ConversationSnapshot.Turn>) -> Content
    @ViewBuilder let header: () -> Header
    @ViewBuilder let footer: () -> Footer
    /// When false the footer is not inserted as a `List` row, so hiding chips does not leave
    /// `listRowSpacing` from an `EmptyView`.
    let showsFooter: Bool

    @State private var isScrolledAway = false
    @State private var isInitialLoad = true
    @State private var scrollTask = ScrollTaskBox()
    @State private var history = HistoryPaginator()

    var body: some View {
        ScrollViewReader { proxy in
            self.conversation(proxy)
                .overlay(alignment: .bottom) { self.scrollToBottomButton(proxy) }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: self.snapshot, initial: true) { _, snapshot in
                    let lastID = self.isScrolledAway ? nil : snapshot.turns.last?.id
                    self.scrollToNewest(lastID, proxy: proxy, animated: !self.isInitialLoad)
                    self.isInitialLoad = false
                }
                .onChange(of: self.isInputFocused) { _, focused in
                    if focused {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy, animated: true)
                    }
                }
                .onChange(of: self.composerClearance) { _, height in
                    if height > 0, self.isInputFocused || !self.isScrolledAway {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy, animated: true)
                    }
                }
        }
    }
}

// MARK: - Subviews

private extension ConversationBottomFlowingList {

    /// The scrollable list of turns, plus the observer that tracks whether the reader has scrolled
    /// away from the bottom.
    func conversation(_ proxy: ScrollViewProxy) -> some View {
        List {
            Group {
                self.header()

                ForEach(self.snapshot.turns) { turn in
                    self.content(turn)
                        .frame(maxWidth: .infinity, alignment: self.alignment(turn.model))
                        .historyRow(turn.id, in: self.history)
                        .id(turn.id)
                }

                if self.showsFooter {
                    self.footer()
                }

                ConversationComposerClearanceRow(composerHeight: self.composerClearance)
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
        .listRowSpacing(self.appearance.spacing.units(6))
#endif
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY > geometry.visibleRect.height * 0.7
        } action: { _, away in
            if self.isScrolledAway != away { self.isScrolledAway = away }
        }
        .modifier(HistoryPagination(
            paginator: self.history,
            snapshot: self.snapshot,
            proxy: proxy,
            scrollTask: self.scrollTask,
            onLoadOlder: self.onLoadOlder
        ))
    }

    /// Jump-to-bottom control, surfaced only once the reader has scrolled away. Wears the thinking
    /// border while a reply streams.
    func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        IconButton(icon: ChatAppearance.Symbol.scrollToBottom) {
            self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy, animated: true)
        }
        .modifier(ThinkingBorderEffect(isActive: self.snapshot.streamingTurnID != nil, shape: Circle()))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .padding(.bottom, self.appearance.spacing.units(2))
        .opacity(self.isScrolledAway && !self.isInputFocused ? 1 : 0)
        .allowsHitTesting(self.isScrolledAway && !self.isInputFocused)
        .animation(.easeInOut(duration: 0.2), value: self.isScrolledAway)
    }
}

// MARK: - Scroll state

private extension ConversationBottomFlowingList {

    /// Lands on the newest turn. Callers pass `nil` to suppress the scroll (the reader has scrolled away).
    /// programmatic jump interpolates instead of tearing the offset out from under an active gesture.
    func scrollToNewest(_ lastID: UUID?, proxy: ScrollViewProxy, animated: Bool = false) {
        guard lastID != nil else { return }
        // Coalesce rapid requests (streaming, keyboard, geometry): cancel the pending scroll so a burst
        // of events resolves to a single scroll instead of flooding MainActor with stacked tasks.
        self.scrollTask.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(ConversationComposerClearance.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(ConversationComposerClearance.id, anchor: .bottom)
            }
        })
    }

    func alignment(_ turn: ConversationSnapshot.Turn) -> Alignment {
        switch turn {
        case .bot: .leading
        case .system: .center
        case .user: .trailing
        }
    }
}

// MARK: - Equatable

extension ConversationBottomFlowingList: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.isInputFocused == rhs.isInputFocused
            && lhs.composerClearance == rhs.composerClearance
            && lhs.showsFooter == rhs.showsFooter
    }
}
