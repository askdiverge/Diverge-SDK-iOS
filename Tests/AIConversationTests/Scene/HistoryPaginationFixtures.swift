//
//  HistoryPaginationFixtures.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

/// A controllable clock so the cooldown can be crossed without sleeping.
final class PaginationTestClock {
    var now = ContinuousClock.Instant.now
    func advance(_ duration: Duration) { self.now += duration }
}

/// Shared fixtures for the `HistoryPaginator` suites — conform a suite and give it a `clock`.
@MainActor
protocol HistoryPaginationFixtures {
    var clock: PaginationTestClock { get }
}

extension HistoryPaginationFixtures {

    /// A paginator whose reader has already scrolled once — the trigger is armed. The unarmed case
    /// is covered by `unarmedUntilTheReaderScrolls`.
    func makePaginator(anchoring: HistoryPaginator.Anchoring = .edges, armed: Bool = true) -> HistoryPaginator {
        let clock = self.clock
        let paginator = HistoryPaginator(anchoring: anchoring, now: { clock.now })
        if armed { paginator.userScrollBegan() }
        return paginator
    }

    nonisolated static func reading(
        offsetY: CGFloat,
        insetTop: CGFloat = 0,
        contentHeight: CGFloat,
        containerHeight: CGFloat = 800
    ) -> HistoryPaginator.Reading {
        .init(offsetY: offsetY, insetTop: insetTop, contentHeight: contentHeight, containerHeight: containerHeight)
    }

    /// An 800 pt container at the origin with every turn of `snapshot` laid out fully visible.
    static func recordVisibleRows(of snapshot: ConversationSnapshot, in paginator: HistoryPaginator) {
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        for (index, turn) in snapshot.turns.enumerated() {
            paginator.record(rowFrame: CGRect(x: 0, y: 100 + CGFloat(index) * 120, width: 400, height: 80), for: turn.id)
        }
    }

    static var nearTop: HistoryPaginator.Reading { self.reading(offsetY: 100, contentHeight: 2_000) }
    static var atBottom: HistoryPaginator.Reading { self.reading(offsetY: 1_200, contentHeight: 2_000) }

    /// Alternating user/bot turns, oldest first.
    static func snapshot(turns: Int, canLoadOlder: Bool = true) -> ConversationSnapshot {
        var ordered: [Identified<ConversationSnapshot.Turn>] = []
        for index in 0..<turns {
            if index.isMultiple(of: 2) {
                ordered.append(Identified(model: .user([.text(AttributedString("u\(index)"))])))
            } else {
                ordered.append(Identified(model: .bot([.text(AttributedString("b\(index)"))])))
            }
        }
        return ConversationSnapshot(
            turns: ordered,
            streamingTurnID: nil,
            canLoadOlder: canLoadOlder
        )
    }
}

extension HistoryPaginator.Landing {
    var pin: HistoryPaginator.Restore? {
        if case .pin(let restore) = self { return restore }
        return nil
    }
}
