//
//  ConversationView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

/// Lays out a conversation Leading/Trailing
struct ConversationView<Content: View, Header: View, Footer: View>: View {

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
    /// When false the footer is not inserted, so hiding chips does not leave a spacer.
    let showsFooter: Bool

    @State private var isScrolledAway = false
    @State private var scrollTask = ScrollTaskBox()
    @State private var history = HistoryPaginator(anchoring: .exact)

    var body: some View {
        ScrollViewReader { proxy in
            self.conversation(proxy)
                .overlay(alignment: .bottom) { self.scrollToBottomButton(proxy) }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: self.snapshot, initial: true) { _, snapshot in
                    self.scrollToNewest(self.isScrolledAway ? nil : snapshot.turns.last?.id, proxy: proxy)
                }
                .onChange(of: self.isInputFocused) { _, focused in
                    if focused {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy)
                    }
                }
                .onChange(of: self.composerClearance) { _, height in
                    if height > 0, self.isInputFocused || !self.isScrolledAway {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy)
                    }
                }
        }
    }
}

// MARK: - Subviews

private extension ConversationView {

    /// The scrollable list of turns, plus the observer that tracks whether the reader has scrolled
    /// away from the bottom.
    func conversation(_ proxy: ScrollViewProxy) -> some View {
        let turns = self.snapshot.turns
        return ScrollView {
            LazyVStack(spacing: self.appearance.spacing.units(11)) {
                Section {
                    ForEach(turns) { turn in
                        self.content(turn)
                            .frame(maxWidth: .infinity, alignment: turn.model.alignment)
                            .transition(.opacity)
                            .historyRow(turn.id, in: self.history)
                            .id(turn.id)
                    }
                    if self.showsFooter {
                        self.footer()
                    }
                    ConversationComposerClearanceRow(composerHeight: self.composerClearance)
                } header: {
                    self.header()
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, self.appearance.spacing.units(4))
        }
        .onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.1) { visibleIDs in
            let atBottom = self.snapshot.turns.last.map { visibleIDs.contains($0.id) } ?? true
            if self.isScrolledAway == atBottom { self.isScrolledAway = !atBottom }
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
            self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy)
        }
        .modifier(ThinkingBorderEffect(isActive: self.snapshot.streamingTurnID != nil, shape: Circle()))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .padding(.bottom, self.appearance.spacing.units(2))
        .opacity(self.isScrolledAway ? 1 : 0)
        .allowsHitTesting(self.isScrolledAway)
        .animation(.easeInOut(duration: 0.2), value: self.isScrolledAway)
    }
}

// MARK: - Scroll state

private extension ConversationView {
    /// Lands on the newest turn. Callers pass `nil` to suppress the scroll (e.g. the reader has
    /// scrolled away and we shouldn't yank them back). Yields a frame so a just-appended row is laid out
    /// before we target it, and eases the jump so it interpolates instead of tearing the offset out from
    /// under an active pan gesture.
    func scrollToNewest(_ lastID: UUID?, proxy: ScrollViewProxy) {
        guard lastID != nil else { return }
        // Coalesce rapid requests (streaming, keyboard, geometry): cancel the pending scroll so a burst
        // of events resolves to a single scroll instead of flooding MainActor with stacked tasks.
        self.scrollTask.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(ConversationComposerClearance.id, anchor: .bottom)
            }
        })
    }
}

// MARK: - Layout

private extension ConversationSnapshot.Turn {
    var alignment: Alignment {
        switch self {
        case .bot, .agent, .note: .leading
        case .system: .center
        case .user: .trailing
        }
    }
}

// MARK: - Equatable
extension ConversationView: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.isInputFocused == rhs.isInputFocused
            && lhs.composerClearance == rhs.composerClearance
            && lhs.showsFooter == rhs.showsFooter
    }
}
