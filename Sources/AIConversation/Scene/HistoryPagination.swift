//
//  HistoryPagination.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// Attaches near-top detection, the load, the restore, and the top-edge loading spinner / retry
/// bar to a conversation container. Apply it directly to the `List` / `ScrollView`, beside the
/// container's other geometry observers, and mark each turn row with
/// ``SwiftUI/View/historyRow(_:in:)``.
///
/// A row pin goes through the container's own ``ScrollTaskBox`` so it coalesces with, and can be
/// cancelled by, any `scrollToNewest` the container issues in the same burst. A content-offset
/// shift is applied at once — it is a correction to the frame that just laid out, not a scroll.
///
/// The spinner and the retry bar are overlays, not list rows — appearing and disappearing costs
/// no layout height and cannot itself shift the reader.
struct HistoryPagination: ViewModifier {

    @Environment(\.appearance) private var appearance

    let paginator: HistoryPaginator
    let snapshot: ConversationSnapshot
    let proxy: ScrollViewProxy
    let scrollTask: ScrollTaskBox
    let onLoadOlder: () async -> HistoryLoadOutcome

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                self.paginator.record(containerFrame: $0)
            }
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
                let reading = HistoryPaginator.Reading(
                    offsetY: geometry.contentOffset.y,
                    insetTop: geometry.contentInsets.top,
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
                switch self.paginator.tick(reading, snapshot: self.snapshot) {
                case .pin(let restore): self.apply(restore)
                case .shift(let delta): self.paginator.shiftContentOffset?(delta)
                case nil: break
                }
            }
            .task(id: self.paginator.loadRequest) {
                guard self.paginator.loadRequest != nil else { return }
                await self.paginator.load(using: self.onLoadOlder)
            }
            .onChange(of: self.paginator.reissueCount) { _, _ in
                guard let settling = self.paginator.settling else { return }
                if settling.shifted != nil {
                    self.paginator.shiftContentOffset?(self.paginator.correction)
                } else {
                    self.apply(settling.restore)
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating { self.paginator.userScrollBegan() }
            }
            .onChange(of: self.snapshot.turns.first?.id) { _, firstTurnID in
                self.paginator.prependLanded(firstTurnID: firstTurnID)
            }
#if canImport(UIKit)
            .background {
                ListScrollViewResolver { self.paginator.shiftContentOffset = $0 }
                    .frame(width: 0, height: 0)
            }
#endif
            .overlay(alignment: .top) {
                if self.paginator.isLoading {
                    ProgressView()
                        .tint(self.appearance.theme.accent)
                        .padding(self.appearance.spacing.units(3))
                        .accessibilityLabel(L10n.historyLoading.string)
                } else if self.paginator.loadFailed {
                    HistoryRetryBar { self.paginator.retry(snapshot: self.snapshot) }
                }
            }
    }

    /// Pins the captured row back to where it was, un-animated, now that the prepend has laid out.
    private func apply(_ restore: HistoryPaginator.Restore) {
        self.scrollTask.replace(with: Task { @MainActor in
            if Task.isCancelled { return }
            self.proxy.scrollTo(restore.row, anchor: restore.anchor)
        })
    }
}

extension View {

    /// Reports this turn row's frame to `paginator` so a prepend can pin the reader to the row
    /// they were looking at. Apply to every row the container renders, alongside `.id(_:)`.
    func historyRow(_ id: UUID, in paginator: HistoryPaginator) -> some View {
        self
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                paginator.record(rowFrame: $0, for: id)
            }
            .onDisappear { paginator.forget(row: id) }
    }
}
