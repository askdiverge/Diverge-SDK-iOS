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
struct ConversationBottomFlowingList<Content: View, Header: View>: View {

    @Environment(\.appearance) private var appearance

    let snapshot: ConversationSnapshot

    /// Whether the input holds focus. Gaining focus scrolls to the newest turn — selecting the field to
    /// reply shouldn't leave the reader up in history, and it pins the latest message above the keyboard.
    let isInputFocused: Bool
    /// A form field has the keyboard, and the jump-to-newest button stays off it.
    let isEditingForm: Bool

    /// Loads the next older page, returning whether it loaded.
    let onLoadOlder: () async -> Bool

    @ViewBuilder let content: (Identified<ConversationSnapshot.Turn>) -> Content
    @ViewBuilder let header: () -> Header

    @State private var isScrolledAway = false
    @State private var isInitialLoad = true
    @State private var scrollTask = ScrollTaskBox()
    @State private var olderTurns = OlderTurnsAnchor()

    var body: some View {
        ScrollViewReader { proxy in
            self.conversation(proxy)
                .overlay(alignment: .bottomTrailing) {
                    ScrollToBottomButton(
                        isVisible: self.isScrolledAway && !self.isInputFocused && !self.isEditingForm && self.snapshot.turns.count > 1,
                        isStreaming: self.snapshot.streamingTurnID != nil
                    ) {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy, animated: true)
                    }
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: self.snapshot, initial: true) { old, new in
                    if let turnID = self.olderTurns.landing(from: old.turns.map(\.id), to: new.turns.map(\.id)) {
                        self.scrollTask.land(on: turnID, proxy: proxy)
                        return
                    }
                    let lastID = self.isScrolledAway ? nil : new.turns.last?.id
                    self.scrollToNewest(lastID, proxy: proxy, animated: !self.isInitialLoad)
                    self.isInitialLoad = false
                }
                .onChange(of: self.isInputFocused) { _, focused in
                    if focused {
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

                if self.snapshot.canLoadOlder {
                    LoadEarlierButton { await self.loadEarlier() }
                }

                ForEach(self.snapshot.turns) { turn in
                    self.content(turn)
                        .frame(maxWidth: .infinity, alignment: self.alignment(turn.model))
                        .id(turn.id)
                }
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
        .listRowSpacing(self.appearance.spacing.units(6))
#endif
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY > geometry.visibleRect.height * 0.7
        } action: { _, away in
            if self.isScrolledAway != away { self.isScrolledAway = away }
        }
    }

}

// MARK: - Scroll state

private extension ConversationBottomFlowingList {

    /// Lands on the newest turn. Callers pass `nil` to suppress the scroll (the reader has scrolled away).
    /// programmatic jump interpolates instead of tearing the offset out from under an active gesture.
    func scrollToNewest(_ lastID: UUID?, proxy: ScrollViewProxy, animated: Bool = false) {
        guard let lastID else { return }
        // Coalesce rapid requests (streaming, keyboard, geometry): cancel the pending scroll so a burst
        // of events resolves to a single scroll instead of flooding MainActor with stacked tasks.
        self.scrollTask.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        })
    }

    func loadEarlier() async {
        self.olderTurns.arm(at: self.snapshot.turns.first?.id)
        if await !self.onLoadOlder() {
            self.olderTurns.disarm()
        }
    }

    func alignment(_ turn: ConversationSnapshot.Turn) -> Alignment {
        switch turn {
        case .bot: .leading
        case .user: .trailing
        }
    }
}

// MARK: - Equatable

extension ConversationBottomFlowingList: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.isInputFocused == rhs.isInputFocused
            && lhs.isEditingForm == rhs.isEditingForm
    }
}
