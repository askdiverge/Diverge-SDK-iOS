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

@Suite("HistoryPaginator — trigger / load / cooldown")
@MainActor
struct HistoryPaginationTests: HistoryPaginationFixtures {

    let clock = PaginationTestClock()

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
}
