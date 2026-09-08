//
//  HistoryPaginationTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("HistoryPaginator.Reading — near-top predicate")
struct HistoryPaginationReadingTests {

    @Test("reports the distance within one viewport of the top of a scrollable conversation")
    func nearTopWithinViewport() {
        #expect(HistoryPaginationTests.reading(offsetY: 100, contentHeight: 2_000).nearTopDistance == 100)
    }

    @Test("at the absolute top under a non-zero top inset the distance is zero")
    func atTopWithInset() {
        // At rest under a top safe-area inset, contentOffset.y is typically -insetTop.
        #expect(HistoryPaginationTests.reading(offsetY: -47, insetTop: 47, contentHeight: 2_000).nearTopDistance == 0)
    }

    @Test("nil at the bottom of a tall conversation")
    func atBottom() {
        #expect(HistoryPaginationTests.reading(offsetY: 1_200, contentHeight: 2_000).nearTopDistance == nil)
    }

    @Test("nil exactly one viewport from the top — the zone is open at the far edge")
    func oneViewportAway() {
        #expect(HistoryPaginationTests.reading(offsetY: 800, contentHeight: 2_000).nearTopDistance == nil)
    }

    @Test("nil when content is shorter than the container")
    func shortContentNeverTriggers() {
        #expect(HistoryPaginationTests.reading(offsetY: 0, contentHeight: 400).nearTopDistance == nil)
    }

    @Test("nil when content height equals the container")
    func equalHeightNeverTriggers() {
        #expect(HistoryPaginationTests.reading(offsetY: 0, contentHeight: 800).nearTopDistance == nil)
    }
}

@Suite("HistoryPaginator — trigger / load / restore")
@MainActor
struct HistoryPaginationTests {

    /// A controllable clock so the cooldown can be crossed without sleeping.
    final class Clock {
        var now = ContinuousClock.Instant.now
        func advance(_ duration: Duration) { self.now += duration }
    }

    let clock = Clock()

    /// A paginator whose reader has already scrolled once — the trigger is armed. The unarmed case
    /// is covered by `unarmedUntilTheReaderScrolls`.
    func makePaginator(anchoring: HistoryPaginator.Anchoring = .edges, armed: Bool = true) -> HistoryPaginator {
        let clock = self.clock
        let paginator = HistoryPaginator(anchoring: anchoring, now: { clock.now })
        if armed { paginator.userScrollBegan() }
        return paginator
    }

    @Test("no trigger before the reader has scrolled — the open frame at offset 0 is not a reader at the top")
    func unarmedUntilTheReaderScrolls() {
        let paginator = self.makePaginator(armed: false)
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.loadRequest == nil)

        paginator.userScrollBegan()
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.loadRequest != nil)
    }

    // MARK: trigger

    @Test("a near-top reading with history left records the first turn and requests a load")
    func triggerRecordsAnchor() {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)

        #expect(paginator.tick(Self.nearTop, snapshot: snapshot) == nil)
        #expect(paginator.pendingAnchor == snapshot.turns.first?.id)
        #expect(paginator.loadRequest != nil)
        #expect(paginator.isBusy)
    }

    @Test("no trigger away from the top")
    func noTriggerAwayFromTop() {
        let paginator = self.makePaginator()

        _ = paginator.tick(Self.atBottom, snapshot: Self.snapshot(turns: 3))
        #expect(paginator.pendingAnchor == nil)
        #expect(paginator.loadRequest == nil)
    }

    @Test("no trigger once history is exhausted")
    func noTriggerWhenExhausted() {
        let paginator = self.makePaginator()

        _ = paginator.tick(Self.nearTop, snapshot: Self.snapshot(turns: 3, canLoadOlder: false))
        #expect(paginator.loadRequest == nil)
    }

    @Test("no trigger with nothing loaded to anchor to")
    func noTriggerWithoutTurns() {
        let paginator = self.makePaginator()

        _ = paginator.tick(Self.nearTop, snapshot: Self.snapshot(turns: 0))
        #expect(paginator.loadRequest == nil)
    }

    @Test("no second trigger while a load is in flight; the request token is untouched")
    func singleFlight() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        let request = paginator.loadRequest

        let gate = AsyncGate()
        let load = Task { await paginator.load { await gate.wait(); return .prepended } }
        for _ in 0..<100 where !paginator.isLoading { await Task.yield() }
        #expect(paginator.isLoading)

        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.loadRequest == request)

        await gate.open()
        await load.value
        #expect(!paginator.isLoading)
    }

    @Test("no trigger while a prepend is pending or awaiting layout — the stale offset must not chain-load")
    func noChainLoadWhileRestoring() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        Self.recordVisibleRows(of: before, in: paginator)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        let request = paginator.loadRequest
        await paginator.load { .prepended }

        // Load returned, prepend not yet committed: still pending.
        _ = paginator.tick(Self.nearTop, snapshot: before)
        #expect(paginator.loadRequest == request)

        // Prepend committed, layout not yet reflected in the geometry: awaiting.
        let after = Self.snapshot(turns: 6)
        #expect(paginator.prependLanded(firstTurnID: after.turns.first?.id))
        _ = paginator.tick(Self.nearTop, snapshot: after)
        #expect(paginator.loadRequest == request)
    }

    // MARK: load

    @Test("a load that prepends keeps the anchor for the restore")
    func successfulLoadKeepsAnchor() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)

        await paginator.load { .prepended }

        #expect(paginator.pendingAnchor == snapshot.turns.first?.id)
        #expect(!paginator.isLoading)
    }

    @Test("a load that prepends nothing drops the anchor — no restore for a failed or no-op load")
    func noOpLoadDropsAnchor() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)

        await paginator.load { .nothing }

        #expect(paginator.pendingAnchor == nil)
        #expect(!paginator.isBusy)
        #expect(!paginator.prependLanded(firstTurnID: UUID()))
        #expect(paginator.tick(Self.reading(offsetY: 0, contentHeight: 9_000), snapshot: snapshot) == nil)
    }

    @Test("load without a request is a no-op")
    func loadWithoutRequest() async {
        let paginator = self.makePaginator()
        var called = false

        await paginator.load { called = true; return .prepended }

        #expect(!called)
    }

    // MARK: cooldown

    @Test("after a no-op load the next trigger waits out the cooldown, then fires again")
    func cooldownAfterNoOp() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        let failedRequest = paginator.loadRequest
        await paginator.load { .nothing }

        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.pendingAnchor == nil)
        #expect(paginator.loadRequest == failedRequest)

        self.clock.advance(HistoryPaginator.retryCooldown)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.pendingAnchor == snapshot.turns.first?.id)
        #expect(paginator.loadRequest != failedRequest)
    }

    @Test("a successful load arms no cooldown — a still-near-top reader keeps loading")
    func noCooldownAfterSuccess() async throws {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        Self.recordVisibleRows(of: before, in: paginator)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        let firstRequest = paginator.loadRequest
        await paginator.load { .prepended }
        let after = Self.snapshot(turns: 6)
        paginator.prependLanded(firstTurnID: after.turns.first?.id)
        let restore = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: after)
        let pinned = try #require(restore?.pin)
        paginator.record(rowFrame: CGRect(x: 0, y: pinned.expectedTop, width: 400, height: 80), for: pinned.row) // settled
        #expect(!paginator.isBusy)

        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: after)
        #expect(paginator.loadRequest != firstRequest)
        #expect(paginator.pendingAnchor == after.turns.first?.id)
    }

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

    // MARK: offset shift (List with a resolved scroll view)

    @Test("with a content-offset shifter the landing is the prepend's laid-out height, no row needed")
    func shiftLanding() async {
        let paginator = self.makePaginator()
        paginator.shiftContentOffset = { _ in }
        let before = Self.snapshot(turns: 3)
        // No row frames recorded at all — the shift does not depend on a visible row.
        _ = paginator.tick(Self.reading(offsetY: 100, contentHeight: 2_000), snapshot: before)
        await paginator.load { .prepended }

        let after = Self.snapshot(turns: 6)
        #expect(paginator.prependLanded(firstTurnID: after.turns.first?.id))
        #expect(paginator.isBusy)
        #expect(paginator.tick(Self.reading(offsetY: 100, contentHeight: 2_000), snapshot: after) == nil)

        // The prepend laid out 8 800 pt above the reader, and List nudged the offset by −13 on the
        // insert → the shift lands the offset on 100 + 8 800 regardless: 8 813. Nothing to verify
        // against, so the cycle is over.
        #expect(paginator.tick(Self.reading(offsetY: 87, contentHeight: 10_800), snapshot: after) == .shift(8_813))
        #expect(!paginator.isBusy)
        #expect(paginator.settling == nil)

        // The corrected offset is far from the top: no chain load.
        #expect(paginator.tick(Self.reading(offsetY: 8_900, contentHeight: 10_800), snapshot: after) == nil)
        #expect(paginator.loadRequest != nil)
        #expect(paginator.pendingAnchor == nil)
    }

    @Test("a shift is verified against the topmost visible row; a re-measure residual is shifted away, a stale frame is not")
    func shiftVerifiedAndCorrected() async {
        let paginator = self.makePaginator()
        paginator.shiftContentOffset = { _ in }
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 100, width: 400, height: 700))
        paginator.record(rowFrame: CGRect(x: 0, y: 300, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.reading(offsetY: 60, contentHeight: 2_000), snapshot: before)
        await paginator.load { .prepended }
        let after = Self.snapshot(turns: 6)
        paginator.prependLanded(firstTurnID: after.turns.first?.id)

        #expect(paginator.tick(Self.reading(offsetY: 60, contentHeight: 8_860), snapshot: after) == .shift(6_860))
        #expect(paginator.isBusy) // settling: the row must come back to y = 300
        #expect(paginator.settling?.shifted == 6_860)

        // A frame from between the commit and the shift shows the row 6 860 pt down: stale, ignored.
        paginator.record(rowFrame: CGRect(x: 0, y: 7_160, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 0)
        #expect(paginator.isBusy)

        // List re-measured a row above after the shift: the row sits 18.67 pt low → correct by that.
        paginator.record(rowFrame: CGRect(x: 0, y: 318.67, width: 400, height: 100), for: row)
        #expect(paginator.reissueCount == 1)
        #expect(abs(paginator.correction - 18.67) < 0.001)
        #expect(paginator.isBusy)

        // Back on target → done.
        paginator.record(rowFrame: CGRect(x: 0, y: 300.2, width: 400, height: 100), for: row)
        #expect(!paginator.isBusy)
        #expect(paginator.reissueCount == 1)
    }

    @Test("a shift after a short page leaves the reader near the top and the next page loads at once")
    func shiftThenChainLoad() async {
        let paginator = self.makePaginator()
        paginator.shiftContentOffset = { _ in }
        let before = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.reading(offsetY: 100, contentHeight: 2_000), snapshot: before)
        let firstRequest = paginator.loadRequest
        await paginator.load { .prepended }
        let after = Self.snapshot(turns: 4)
        paginator.prependLanded(firstTurnID: after.turns.first?.id)
        #expect(paginator.tick(Self.reading(offsetY: 100, contentHeight: 2_300), snapshot: after) == .shift(300))

        _ = paginator.tick(Self.reading(offsetY: 400, contentHeight: 2_300), snapshot: after)
        #expect(paginator.loadRequest != firstRequest)
    }

    // MARK: settle timeout

    @Test("a pin whose row never reports back stops being busy once the settle window has passed")
    func settleExpiresOnTick() async {
        let paginator = self.makePaginator()
        let before = Self.snapshot(turns: 3)
        let row = before.turns[1].id
        paginator.record(containerFrame: CGRect(x: 0, y: 0, width: 400, height: 800))
        paginator.record(rowFrame: CGRect(x: 0, y: 200, width: 400, height: 100), for: row)
        _ = paginator.tick(Self.nearTop, snapshot: before)
        await paginator.load { .prepended }
        paginator.prependLanded(firstTurnID: UUID())
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: before)
        #expect(paginator.isBusy)

        // Landed exactly where it was → no frame change → no record(rowFrame:) ever comes.
        _ = paginator.tick(Self.reading(offsetY: 9_000, contentHeight: 2_300), snapshot: before)
        #expect(paginator.isBusy)
        self.clock.advance(HistoryPaginator.settleWindow + .milliseconds(1))
        _ = paginator.tick(Self.reading(offsetY: 9_000, contentHeight: 2_300), snapshot: before)
        #expect(!paginator.isBusy)
    }

    // MARK: failure and retry

    @Test("a failed load raises loadFailed; a no-op load does not")
    func failedLoadFlag() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        await paginator.load { .failed }
        #expect(paginator.loadFailed)
        #expect(paginator.pendingAnchor == nil)
        #expect(!paginator.isBusy)

        self.clock.advance(HistoryPaginator.retryCooldown + .milliseconds(1))
        paginator.userScrollBegan()
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(!paginator.loadFailed) // the next request clears it
        await paginator.load { .nothing }
        #expect(!paginator.loadFailed)
    }

    @Test("after a failure the scroll trigger waits for the reader to scroll, not just for the cooldown")
    func failureNeedsScrollToRetry() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        let failedRequest = paginator.loadRequest
        await paginator.load { .failed }
        self.clock.advance(HistoryPaginator.retryCooldown + .milliseconds(1))

        // List re-measuring rows under a still reader produces geometry samples — no retry.
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_012), snapshot: snapshot)
        _ = paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_000), snapshot: snapshot)
        #expect(paginator.loadRequest == failedRequest)
        #expect(paginator.loadFailed)

        // The reader scrolls → the next near-top sample retries.
        paginator.userScrollBegan()
        _ = paginator.tick(Self.reading(offsetY: 40, contentHeight: 2_000), snapshot: snapshot)
        #expect(paginator.loadRequest != failedRequest)

        // A no-op load (busy / exhausted / empty) needs only the cooldown.
        await paginator.load { .nothing }
        let noopRequest = paginator.loadRequest
        self.clock.advance(HistoryPaginator.retryCooldown)
        _ = paginator.tick(Self.reading(offsetY: 40, contentHeight: 2_000), snapshot: snapshot)
        #expect(paginator.loadRequest != noopRequest)
    }

    @Test("retry re-requests the page at once, ignoring the cooldown, and only after a failure")
    func retryBypassesCooldown() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)

        paginator.retry(snapshot: snapshot) // nothing failed yet
        #expect(paginator.loadRequest == nil)

        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        let failedRequest = paginator.loadRequest
        await paginator.load { .failed }
        #expect(paginator.tick(Self.nearTop, snapshot: snapshot) == nil)
        #expect(paginator.loadRequest == failedRequest) // cooldown holds the scroll trigger

        paginator.retry(snapshot: snapshot)
        #expect(paginator.loadRequest != failedRequest)
        #expect(paginator.pendingAnchor == snapshot.turns.first?.id)
        #expect(!paginator.loadFailed)

        // A retry while the retry is in flight, or once history is exhausted, is ignored.
        let request = paginator.loadRequest
        paginator.retry(snapshot: snapshot)
        #expect(paginator.loadRequest == request)
        await paginator.load { .failed }
        paginator.retry(snapshot: Self.snapshot(turns: 3, canLoadOlder: false))
        #expect(paginator.loadRequest == request)
    }

    @Test("leaving the top zone dismisses the failed state")
    func failedStateClearsAwayFromTop() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        await paginator.load { .failed }
        #expect(paginator.loadFailed)

        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        #expect(paginator.loadFailed) // still near the top: keep offering the retry
        _ = paginator.tick(Self.atBottom, snapshot: snapshot)
        #expect(!paginator.loadFailed)
    }

    @Test("a prepend with no visible row to pin owes nothing and does not stay busy")
    func prependWithoutRowsOwesNothing() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        await paginator.load { .prepended }

        #expect(!paginator.prependLanded(firstTurnID: UUID()))
        #expect(!paginator.isBusy)
    }

    @Test("a first-turn change while nothing is pending owes no restore")
    func nothingToRestoreIdle() {
        let paginator = self.makePaginator()
        #expect(!paginator.prependLanded(firstTurnID: UUID()))
        #expect(paginator.tick(Self.reading(offsetY: 0, contentHeight: 2_300), snapshot: Self.snapshot(turns: 3, canLoadOlder: false)) == nil)
    }

    @Test("a first-turn change that keeps the anchor first (no prepend) owes no restore")
    func sameFirstTurnOwesNothing() async {
        let paginator = self.makePaginator()
        let snapshot = Self.snapshot(turns: 3)
        _ = paginator.tick(Self.nearTop, snapshot: snapshot)
        await paginator.load { .prepended }

        #expect(!paginator.prependLanded(firstTurnID: snapshot.turns.first?.id))
        #expect(paginator.pendingAnchor == snapshot.turns.first?.id)
    }
}

// MARK: - Fixtures

extension HistoryPaginationTests {

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

private extension HistoryPaginator.Landing {
    var pin: HistoryPaginator.Restore? {
        if case .pin(let restore) = self { return restore }
        return nil
    }
}
