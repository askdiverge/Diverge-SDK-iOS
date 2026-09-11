//
//  HistoryPaginationRestoreTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("HistoryPaginator — restore / settle")
@MainActor
struct HistoryPaginationRestoreTests: HistoryPaginationFixtures {

    let clock = PaginationTestClock()

    // MARK: restore

    @Test("the restore pins the topmost fully visible row where it was, handed back once the content grew")
    func restoreAfterPrepend() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let rows = before.turns.map(\.id)
        // The container's laid-out frame is the visible viewport: 700 tall from y=100.
        paginator.record(containerFrame: CGRect(x: 0, y: 100, width: 400, height: 700))
        paginator.record(rowFrame: CGRect(x: 0, y: 70, width: 400, height: 60), for: rows[0])   // straddles the top
        paginator.record(rowFrame: CGRect(x: 0, y: 250, width: 400, height: 100), for: rows[1])
        paginator.record(rowFrame: CGRect(x: 0, y: 396, width: 400, height: 100), for: rows[2]) // 4 pt off centre
        _ = paginator.tick(Self.reading(offsetY: 100, contentHeight: 2_000), snapshot: before)
        await paginator.load { .prepended }
        // The reader kept scrolling during the fetch; the last reading before the commit wins.
        _ = paginator.tick(Self.reading(offsetY: 60, contentHeight: 2_000), snapshot: before)

        let after = Self.snapshot(turns: 6)
        #expect(paginator.prependLanded(firstTurnID: after.turns.first?.id))
        #expect(paginator.pendingAnchor == nil)
        #expect(paginator.isBusy)

        // Geometry still shows the old content height: not laid out yet.
        #expect(paginator.tick(Self.reading(offsetY: 60, contentHeight: 2_000), snapshot: after) == nil)

        // Content grew → the cheapest pin is rows[2] centred (viewport centre 450 → top 400, a 4 pt hop).
        let restore = paginator.tick(Self.reading(offsetY: 60, contentHeight: 2_300), snapshot: after)
        #expect(restore?.pin == .init(row: rows[2], anchor: .center, expectedTop: 400))
        #expect(paginator.isBusy) // settling

        // The pin landed: the row's frame update releases the cycle.
        paginator.record(rowFrame: CGRect(x: 0, y: 400, width: 400, height: 100), for: rows[2])
        #expect(!paginator.isBusy)
        #expect(paginator.reissueCount == 0)
        #expect(paginator.tick(Self.reading(offsetY: 360, contentHeight: 2_300), snapshot: after) == nil)

        // Later growth (a streamed reply) does not restore again.
        #expect(paginator.tick(Self.reading(offsetY: 360, contentHeight: 2_400), snapshot: after) == nil)
    }

    @Test("a pin that landed off target is re-issued until the row is back")
    func settleReissuesUntilRowIsBack() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        let after = Self.snapshot(turns: 6)
        paginator.prependLanded(firstTurnID: after.turns.first?.id)
        let first = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: after)
        #expect(first?.pin == .init(row: row, anchor: .center, expectedTop: 350))

        // List scrolled to estimated attributes: the row's own frame update says it sits 150 pt low
        // → the same pin is re-issued (the modifier observes reissueCount).
        paginator.record(rowFrame: CGRect(x: 0, y: 500, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 1)
        #expect(paginator.settling?.restore == first?.pin)
        #expect(paginator.isBusy)

        // Second pass lands within tolerance → done.
        paginator.record(rowFrame: CGRect(x: 0, y: 350.4, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 1)
        #expect(!paginator.isBusy)

        // Scroll samples during the settle never trigger or restore.
        #expect(paginator.tick(Self.reading(offsetY: 9_160, contentHeight: 2_300), snapshot: after) == nil)
    }

    @Test("other rows' frame updates do not affect the settle check")
    func settleIgnoresOtherRows() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        paginator.prependLanded(firstTurnID: UUID())
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: before)

        paginator.record(rowFrame: CGRect(x: 0, y: 900, width: 400, height: 100), for: before.turns[2].id)
        #expect(paginator.reissueCount == 0)
        #expect(paginator.isBusy)
    }

    @Test("settling gives up after maxSettleAttempts, and immediately if the pinned row is gone")
    func settleBounded() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        let after = Self.snapshot(turns: 6)
        paginator.prependLanded(firstTurnID: after.turns.first?.id)
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: after)

        // Never lands: bounded re-issues, then release.
        for _ in 0..<10 {
            paginator.record(rowFrame: CGRect(x: 0, y: 500, width: 400, height: 100), for: row)
        }
        #expect(paginator.reissueCount == HistoryPaginator.maxSettleAttempts - 1)
        #expect(!paginator.isBusy)

        // Row recycled out of the hierarchy mid-settle → stop at once.
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: after)
        await paginator.load { .prepended }
        paginator.prependLanded(firstTurnID: UUID())
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 3_000), snapshot: after)
        #expect(paginator.isBusy)
        paginator.forget(row: row)
        #expect(!paginator.isBusy)
        #expect(paginator.reissueCount == HistoryPaginator.maxSettleAttempts - 1)
    }

    @Test("restore target considers only rows fully inside the viewport and picks the smallest hop")
    func restoreTargetSelection() {
        let clipped = UUID(), inside = UUID(), overflowing = UUID()
        let rows = [
            clipped: CGRect(x: 0, y: 90, width: 400, height: 40),      // crosses the viewport top (100) → out
            inside: CGRect(x: 0, y: 300, width: 400, height: 100),     // top: 200 off · centre: 100 off · bottom: 400 off
            overflowing: CGRect(x: 0, y: 700, width: 400, height: 200) // crosses the bottom (800) → out
        ]
        let viewport = CGRect(x: 0, y: 100, width: 400, height: 700)
        let restore = HistoryPaginator.restore(rows: rows, viewport: viewport, anchoring: .edges)
        #expect(restore == .init(row: inside, anchor: .center, expectedTop: 400))
    }

    @Test("restore target uses .top and .bottom when those are the nearest landings")
    func restoreTargetEdges() {
        let viewport = CGRect(x: 0, y: 100, width: 400, height: 700)
        let nearTop = UUID(), nearBottom = UUID()

        let top = HistoryPaginator.restore(rows: [nearTop: CGRect(x: 0, y: 103, width: 400, height: 50)], viewport: viewport, anchoring: .edges)
        #expect(top == .init(row: nearTop, anchor: .top, expectedTop: 100))

        let bottom = HistoryPaginator.restore(rows: [nearBottom: CGRect(x: 0, y: 745, width: 400, height: 50)], viewport: viewport, anchoring: .edges)
        #expect(bottom == .init(row: nearBottom, anchor: .bottom, expectedTop: 750))
    }

    @Test("exact anchoring pins the topmost visible row to its own position")
    func restoreTargetExact() {
        let upper = UUID(), lower = UUID()
        let rows = [
            upper: CGRect(x: 0, y: 300, width: 400, height: 100),
            lower: CGRect(x: 0, y: 500, width: 400, height: 100)
        ]
        let viewport = CGRect(x: 0, y: 100, width: 400, height: 700)
        // The row sits 200 pt into 600 pt of slack → anchor y = 1/3, and it lands back on y = 300.
        let restore = HistoryPaginator.restore(rows: rows, viewport: viewport, anchoring: .exact)
        #expect(restore?.row == upper)
        #expect(restore?.expectedTop == 300)
        #expect(abs((restore?.anchor.y ?? 0) - 1.0 / 3.0) < 0.0001)

        // The exact paginator hands that restore out after a prepend.
        let paginator = self.makePaginator(anchoring: .exact)
        let before = Self.snapshot(turns: 3)
        paginator.record(containerFrame: viewport)
        paginator.record(rowFrame: rows[upper]!, for: before.turns[1].id)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        #expect(paginator.prependLanded(firstTurnID: UUID()))
        let landed = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: before)
        #expect(landed?.pin?.row == before.turns[1].id)
        #expect(landed?.pin?.expectedTop == 300)
    }

    @Test("the settle window closes on time and when the reader scrolls")
    func settleWindowAndUserScroll() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        paginator.prependLanded(firstTurnID: UUID())
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: before)

        // A late frame update (the reader dragged the row away) is not a failed landing.
        self.clock.advance(HistoryPaginator.settleWindow + .milliseconds(1))
        paginator.record(rowFrame: CGRect(x: 0, y: 500, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 0)
        #expect(!paginator.isBusy)

        // Explicit user scroll ends the settle at once.
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        paginator.prependLanded(firstTurnID: UUID())
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 3_000), snapshot: before)
        #expect(paginator.isBusy)
        paginator.userScrollBegan()
        #expect(!paginator.isBusy)
        paginator.record(rowFrame: CGRect(x: 0, y: 500, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 0)
    }

    @Test("no restore target when no row is fully visible")
    func restoreTargetNone() {
        let rows = [UUID(): CGRect(x: 0, y: -10, width: 400, height: 900)]
        #expect(HistoryPaginator.restore(rows: rows, viewport: CGRect(x: 0, y: 0, width: 400, height: 800), anchoring: .edges) == nil)
        #expect(HistoryPaginator.restore(rows: rows, viewport: CGRect(x: 0, y: 0, width: 400, height: 800), anchoring: .exact) == nil)
    }

    @Test("a forgotten row is never the restore target")
    func forgottenRowSkipped() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let rows = before.turns.map(\.id)
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 100, width: 400, height: 50), for: rows[0])
        paginator.record(rowFrame: CGRect(x: 0, y: 300, width: 400, height: 50), for: rows[1])
        paginator.forget(row: rows[0])
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }

        #expect(paginator.prependLanded(firstTurnID: UUID()))
        #expect(paginator.awaitingLayout?.restore?.row == rows[1])
    }
}
