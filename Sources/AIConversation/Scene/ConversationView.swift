//
//  ConversationView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-19.
//

import SwiftUI
import AIConversationEngine

/// Lays out a conversation Leading/Trailing
struct ConversationView<Content: View, Header: View>: View {

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
    @State private var scrollTask = ScrollTaskBox()
    @State private var olderTurns = OlderTurnsAnchor()

    var body: some View {
        ScrollViewReader { proxy in
            self.conversation(proxy)
                .overlay(alignment: .bottom) {
                    ScrollToBottomButton(
                        isVisible: self.isScrolledAway && !self.isEditingForm && self.snapshot.turns.count > 1,
                        isStreaming: self.snapshot.streamingTurnID != nil
                    ) {
                        self.scrollToNewest(self.snapshot.turns.last?.id, proxy: proxy)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onChange(of: self.snapshot, initial: true) { old, new in
                    if case .landed(let turnID?) = self.olderTurns.landing(from: old.turns, to: new.turns) {
                        self.scrollTask.land(on: turnID, proxy: proxy)
                        return
                    }
                    self.scrollToNewest(self.isScrolledAway ? nil : new.turns.last?.id, proxy: proxy)
                }
                .onChange(of: self.isInputFocused) { _, focused in
                    if focused {
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
                    if self.snapshot.canLoadOlder {
                        LoadEarlierButton { await self.loadEarlier() }
                    }

                    ForEach(turns) { turn in
                        self.content(turn)
                            .frame(maxWidth: .infinity, alignment: turn.model.alignment)
                            .transition(.opacity)
                            .id(turn.id)
                    }
                    FormFieldClearance(isActive: self.isEditingForm)
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
    }

}

// MARK: - Scroll state

private extension ConversationView {
    func loadEarlier() async {
        self.olderTurns.arm(at: self.snapshot.turns.first?.id)
        if await !self.onLoadOlder() {
            self.olderTurns.disarm()
        }
    }

    /// Lands on the newest turn. Callers pass `nil` to suppress the scroll (e.g. the reader has
    /// scrolled away and we shouldn't yank them back). Yields a frame so a just-appended row is laid out
    /// before we target it, and eases the jump so it interpolates instead of tearing the offset out from
    /// under an active pan gesture.
    func scrollToNewest(_ lastID: UUID?, proxy: ScrollViewProxy) {
        guard let lastID else { return }
        // Coalesce rapid requests (streaming, keyboard, geometry): cancel the pending scroll so a burst
        // of events resolves to a single scroll instead of flooding MainActor with stacked tasks.
        self.scrollTask.replace(with: Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        })
    }
}

// MARK: - Layout

private extension ConversationSnapshot.Turn {
    var alignment: Alignment {
        switch self {
        case .bot: .leading
        case .user: .trailing
        }
    }
}

// MARK: - Equatable
extension ConversationView: @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.isInputFocused == rhs.isInputFocused
            && lhs.isEditingForm == rhs.isEditingForm
    }
}
