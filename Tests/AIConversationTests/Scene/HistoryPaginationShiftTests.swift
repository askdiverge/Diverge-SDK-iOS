//
//  HistoryPaginationShiftTests.swift
//  AIConversationTests
//

import Foundation
import SwiftUI
import Testing
@testable import AIConversation
@testable import AIConversationEngine

@Suite("HistoryPaginator — offset shift, failure / retry")
@MainActor
struct HistoryPaginationShiftTests: HistoryPaginationFixtures {

    let clock = PaginationTestClock()

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
