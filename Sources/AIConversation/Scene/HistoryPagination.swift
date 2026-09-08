//
//  HistoryPagination.swift
//  AIConversation
//
//  Created by Mohamed Aldahoul on 2026-09-05.
//

import SwiftUI
import AIConversationEngine

/// How a request for the next older history page went, as the conversation list needs to know it.
enum HistoryLoadOutcome: Equatable, Sendable {
    /// Older turns landed above the reader — a restore is owed once they lay out.
    case prepended
    /// Nothing changed and nothing is wrong: the provider was busy, exhausted, or the page was
    /// empty.
    case nothing
    /// A recoverable failure; the cursor is kept so the same page can be retried.
    case failed
}

/// Owns the reverse-pagination trigger / load / restore cycle for a conversation list.
///
/// The cycle is split at the snapshot boundary so the scroll is driven by the data actually
/// changing, never by the load call returning:
///
/// 1. ``tick(_:snapshot:)`` — a near-top scroll reading, once the reader has scrolled at all
///    (``userScrollBegan()``), records the oldest loaded turn as ``pendingAnchor`` and requests a
///    load.
/// 2. ``load(using:)`` — awaits the page. A load that prepends nothing drops the anchor and arms a
///    short retry cooldown; no scroll happens. A failure additionally raises ``loadFailed`` so the
///    modifier can offer an inline retry where the reader is looking.
/// 3. ``prependLanded(firstTurnID:)`` — the container's snapshot gains turns above the anchor and
///    `turns.first` changes. Row frames are still pre-layout here, so the position to give back is
///    captured now.
/// 4. The next ``tick(_:snapshot:)`` whose content height differs is the laid-out prepend; it
///    hands back the ``Landing`` that puts the reader where they were.
///
/// Two landings exist because of what the host container can do. When the modifier has resolved
/// the `UIScrollView` behind a `List`, the landing is a ``Landing/shift(_:)`` that puts the
/// content offset at "where the reader was, plus the prepend's laid-out height" — exact, no row
/// involved. Otherwise it is a ``Landing/pin(_:)`` of the topmost fully visible row via
/// `scrollTo(_:anchor:)`, exact on a `ScrollView` and quantised to `List`'s three anchors there
/// (see ``Anchoring``).
///
/// Holds no `ScrollViewProxy`, so every decision above is unit-testable.
@MainActor
@Observable
final class HistoryPaginator {

    /// One `ScrollGeometry` sample, reduced to the numbers the paginator reasons about.
    struct Reading: Equatable, Sendable {
        var offsetY: CGFloat
        var insetTop: CGFloat
        var contentHeight: CGFloat
        var containerHeight: CGFloat

        /// The reader's distance from the top while within one viewport of it, else `nil`.
        ///
        /// Guards on content taller than the container so a short conversation never
        /// self-triggers at rest — every flow opens pinned to the bottom via
        /// `.defaultScrollAnchor(.bottom, for: .initialOffset)`.
        var nearTopDistance: CGFloat? {
            guard self.contentHeight > self.containerHeight else { return nil }
            let distance = self.offsetY + self.insetTop
            return distance < self.containerHeight ? distance : nil
        }
    }

    /// A row pin: `row` scrolled to `anchor`, chosen so the row lands where it was. `expectedTop`
    /// is the row's resulting top edge (container coordinates), used to verify the pin landed and
    /// to re-issue it if `List` scrolled to estimated attributes.
    struct Restore: Equatable {
        let row: UUID
        let anchor: UnitPoint
        let expectedTop: CGFloat
    }

    /// What the modifier does to give the reader their position back after a prepend laid out.
    enum Landing: Equatable {
        /// `scrollTo(restore.row, anchor: restore.anchor)`.
        case pin(Restore)
        /// Add `dy` — the laid-out height of the prepend — to the scroll view's content offset.
        case shift(CGFloat)
    }

    /// Which `UnitPoint`s the host scroll container honours in `scrollTo(_:anchor:)`; decides the
    /// ``Landing/pin(_:)`` when no content-offset shift is available.
    enum Anchoring: Sendable {
        /// `List` maps the anchor onto `UICollectionView.ScrollPosition`: only `.top` / `.center`
        /// / `.bottom` are exact, any fractional point is treated as `.center`. The restore picks
        /// the visible row and edge that move the row least — at most half a row pitch.
        case edges
        /// `ScrollView` honours any fractional anchor, so the topmost visible row is pinned back
        /// to exactly where it was.
        case exact
    }

    /// How many times a pin is issued in total while the pinned row's frame does not match
    /// `expectedTop`.
    static let maxSettleAttempts = 3

    /// Tolerance for the settle check, in points.
    static let settleTolerance: CGFloat = 1

    /// How long after a pin the pinned row's frame updates are still taken as its landing. After
    /// that (or as soon as the reader scrolls) the settle is over — a late re-issue would yank the
    /// reader back to the row.
    static let settleWindow: Duration = .milliseconds(300)

    /// How long a load that changed nothing blocks the next scroll trigger. Without it a no-op
    /// load would be retried on every scroll tick while the reader is still decelerating near the
    /// top. An explicit ``retry(snapshot:)`` ignores it.
    static let retryCooldown: Duration = .seconds(1.5)

    private(set) var isLoading = false

    /// The last load failed and has not been retried yet — the modifier shows the inline retry.
    /// Cleared by the next load request and when the reader leaves the top zone.
    private(set) var loadFailed = false

    /// The scroll trigger fires only once the reader has scrolled. Geometry samples also arrive
    /// while nobody is scrolling: at open the content lays out at offset 0 for a frame before
    /// `.defaultScrollAnchor(.bottom, for: .initialOffset)` places the reader — which reads as
    /// "at the top" — and `List` re-measures rows as they realise. Disarmed again by a failure so a
    /// reader parked at the top does not hammer a failing endpoint every cooldown; re-armed by
    /// ``userScrollBegan()``.
    @ObservationIgnored private var armed = false

    /// The oldest loaded turn at trigger time. Non-nil from the trigger until the prepend lands
    /// or the load proves a no-op.
    private(set) var pendingAnchor: UUID?

    /// Fresh token per requested load — the modifier keys `.task(id:)` on it so the load runs
    /// as structured work owned by the view.
    private(set) var loadRequest: UUID?

    /// Captured by ``prependLanded(firstTurnID:)``: the topmost visible row and where it was, the
    /// last pre-prepend geometry, and which landing is owed; released by the first tick that shows
    /// the content having grown. `restore` is only optional for a shift, which needs no row to land
    /// (it then just goes unverified).
    private(set) var awaitingLayout: (restore: Restore?, before: Reading, viaShift: Bool)?

    /// A landing that has been issued and is being verified against the row's actual frame.
    /// `shifted` is the last content-offset shift applied when the landing was a shift, `nil` for
    /// a pin.
    private(set) var settling: (restore: Restore, attempts: Int, until: ContinuousClock.Instant, shifted: CGFloat?)?

    /// Bumped each time the settle check finds the row off target and the landing must be issued
    /// again; the modifier observes it and re-applies ``settling``'s pin, or shifts the content
    /// offset by ``correction``.
    private(set) var reissueCount = 0

    /// The residual content-offset shift that puts the verified row back, for the modifier to
    /// apply on the next ``reissueCount`` bump of a shift landing.
    private(set) var correction: CGFloat = 0

    /// Set by the modifier once it has the scroll view behind the container: moves the content
    /// offset by the given delta. While present, prepends land by ``Landing/shift(_:)``.
    @ObservationIgnored var shiftContentOffset: ((CGFloat) -> Void)?

    // Geometry bookkeeping — written on every scroll frame, never read in a `body`.
    @ObservationIgnored private var lastReading: Reading?
    @ObservationIgnored private var containerFrame: CGRect = .zero
    @ObservationIgnored private var rowFrames: [UUID: CGRect] = [:]

    private var retryAllowedAt: ContinuousClock.Instant?
    private let anchoring: Anchoring
    private let now: () -> ContinuousClock.Instant

    init(anchoring: Anchoring = .edges, now: @escaping () -> ContinuousClock.Instant = { .now }) {
        self.anchoring = anchoring
        self.now = now
    }

    /// Whether a load / restore cycle is in progress. No new trigger fires meanwhile — in the
    /// frames between the prepend committing and the restore, the stale offset reads as near the
    /// top and would otherwise chain-load the next page.
    var isBusy: Bool {
        self.isLoading || self.pendingAnchor != nil || self.awaitingLayout != nil || self.settling != nil
    }

    // MARK: Geometry feed

    /// The container's frame, in the same coordinate space as the row frames.
    func record(containerFrame: CGRect) {
        self.containerFrame = containerFrame
    }

    /// A realised row's frame. Call ``forget(row:)`` when the row leaves the hierarchy so a stale
    /// frame is never picked as a pin target.
    ///
    /// While a landing is settling, the tracked row's own frame update is the verification: it
    /// arrives after the scroll has laid out, unlike the scroll-geometry sample, which can precede
    /// the row's new frame. Off target → ``reissueCount`` bumps so the modifier pins again, or
    /// shifts by the residual (`List` re-measures a row or two right after a prepend lays out,
    /// which moves the reader by that much after the shift has been applied).
    func record(rowFrame: CGRect, for id: UUID) {
        self.rowFrames[id] = rowFrame

        guard let settling = self.settling, settling.restore.row == id else { return }
        let residual = rowFrame.minY - settling.restore.expectedTop
        if abs(residual) <= Self.settleTolerance
            || settling.attempts >= Self.maxSettleAttempts
            || self.now() > settling.until {
            self.settling = nil
            return
        }
        if let shifted = settling.shifted {
            // A frame captured between the prepend committing and the shift reports the row
            // displaced by exactly the shift; it is stale, not a residual — wait for the next.
            guard abs(residual - shifted) > Self.settleTolerance else { return }
            self.correction = residual
        }
        self.settling = (settling.restore, settling.attempts + 1, self.now() + Self.settleWindow, settling.shifted.map { _ in residual })
        self.reissueCount += 1
    }

    func forget(row id: UUID) {
        self.rowFrames.removeValue(forKey: id)
        if self.settling?.restore.row == id { self.settling = nil }
    }

    /// The reader took over (drag or deceleration): whatever the pin landed on is where they are
    /// now; never re-issue it under their finger. Also arms the scroll trigger (see `armed`).
    func userScrollBegan() {
        self.settling = nil
        self.armed = true
    }

    /// Feed every scroll geometry sample here. Requests a load when the reader is near the top
    /// and one is due; returns the landing to apply once a landed prepend has laid out.
    ///
    /// Level-triggered rather than edge-triggered on purpose: a reader still within one viewport
    /// of the top after a short page lands keeps loading, and a reader who scrolls again after a
    /// failed load retries once the cooldown has passed (a still reader does not — see
    /// ``retry(snapshot:)`` for their affordance).
    func tick(_ reading: Reading, snapshot: ConversationSnapshot) -> Landing? {
        self.lastReading = reading

        // A pin whose row never reported a new frame (it landed exactly where it was) would
        // otherwise stay "settling" — and busy — until the reader scrolled.
        if let settling, self.now() > settling.until { self.settling = nil }

        if let awaiting = self.awaitingLayout {
            guard reading.contentHeight != awaiting.before.contentHeight else { return nil }
            self.awaitingLayout = nil
            let until = self.now() + Self.settleWindow
            if awaiting.viaShift {
                // The rows the reader was on moved down by exactly the content growth; the offset
                // that puts them back is the pre-prepend offset plus that growth. `List` nudges the
                // offset by a few points on the insert itself (its own estimate-based anchoring),
                // so the shift is measured against where the reader *was*, not where the offset is.
                let target = awaiting.before.offsetY + (reading.contentHeight - awaiting.before.contentHeight)
                let shift = target - reading.offsetY
                if let restore = awaiting.restore { self.settling = (restore, 1, until, shift) }
                return .shift(shift)
            }
            guard let restore = awaiting.restore else { return nil }
            self.settling = (restore, 1, until, nil)
            return .pin(restore)
        }

        guard reading.nearTopDistance != nil else {
            self.loadFailed = false
            return nil
        }
        guard !self.isBusy, snapshot.canLoadOlder, let anchor = snapshot.turns.first?.id else { return nil }
        guard self.armed else { return nil }
        if let retryAllowedAt, self.now() < retryAllowedAt { return nil }

        self.request(anchor: anchor)
        return nil
    }

    /// The reader tapped the inline retry after a failed load: request the page again at once,
    /// ignoring the cooldown.
    func retry(snapshot: ConversationSnapshot) {
        guard self.loadFailed, !self.isBusy, snapshot.canLoadOlder, let anchor = snapshot.turns.first?.id else { return }
        self.request(anchor: anchor)
    }

    private func request(anchor: UUID) {
        self.pendingAnchor = anchor
        self.loadRequest = UUID()
        self.loadFailed = false
        self.retryAllowedAt = nil
    }

    // MARK: Cycle

    /// Runs the requested load. Clears the anchor when nothing was prepended so a failed or no-op
    /// load never scrolls; a successful load leaves the anchor for ``prependLanded(firstTurnID:)``.
    func load(using onLoadOlder: () async -> HistoryLoadOutcome) async {
        guard self.loadRequest != nil, !self.isLoading else { return }
        self.isLoading = true
        defer { self.isLoading = false }

        let outcome = await onLoadOlder()
        guard outcome != .prepended else { return }
        self.pendingAnchor = nil
        self.retryAllowedAt = self.now() + Self.retryCooldown
        self.loadFailed = outcome == .failed
        if outcome == .failed { self.armed = false }
    }

    /// Call when the snapshot's first turn changes — before layout, while the recorded row frames
    /// are still the pre-prepend ones. Consumes the anchor exactly once, when the first turn has
    /// moved off it (the older page landed above it), and captures what to give back. Returns
    /// whether a landing is now owed.
    @discardableResult
    func prependLanded(firstTurnID: UUID?) -> Bool {
        guard let pendingAnchor, firstTurnID != pendingAnchor else { return false }
        self.pendingAnchor = nil
        guard let reading = self.lastReading else { return false }

        let viaShift = self.shiftContentOffset != nil
        // A shift needs no row to land, but tracks the topmost visible one (where it *is*) to verify.
        let restore = Self.restore(rows: self.rowFrames, viewport: self.containerFrame, anchoring: viaShift ? .exact : self.anchoring)
        guard viaShift || restore != nil else { return false }
        self.awaitingLayout = (restore, reading, viaShift)
        return true
    }

    /// The pin that moves the reader least, from the rows fully inside `viewport`.
    ///
    /// `.exact`: the topmost such row, pinned to the fractional anchor that lands it back on its
    /// own top edge. `.edges`: every such row against `.top` / `.center` / `.bottom`, keeping the
    /// combination with the smallest hop; ties resolve to the higher row.
    ///
    /// `viewport` is the container's laid-out frame — for a `List` under safe-area insets that is
    /// already the inset (visible) area, which is also the area `scrollTo(_:anchor:)` aligns to.
    static func restore(rows: [UUID: CGRect], viewport: CGRect, anchoring: Anchoring) -> Restore? {
        guard viewport.height > 0 else { return nil }
        let visible = rows
            .filter { $0.value.minY >= viewport.minY && $0.value.maxY <= viewport.maxY }
            .sorted { $0.value.minY < $1.value.minY }

        switch anchoring {
        case .exact:
            guard let (id, frame) = visible.first else { return nil }
            let slack = viewport.height - frame.height
            let y = slack > 0 ? (frame.minY - viewport.minY) / slack : 0
            return Restore(row: id, anchor: UnitPoint(x: 0.5, y: y), expectedTop: frame.minY)

        case .edges:
            var best: (restore: Restore, hop: CGFloat)?
            for (id, frame) in visible {
                let landings: [(UnitPoint, CGFloat)] = [
                    (.top, viewport.minY),
                    (.center, viewport.midY - frame.height / 2),
                    (.bottom, viewport.maxY - frame.height)
                ]
                for (anchor, top) in landings {
                    let hop = abs(top - frame.minY)
                    if best.map({ hop < $0.hop }) ?? true {
                        best = (Restore(row: id, anchor: anchor, expectedTop: top), hop)
                    }
                }
            }
            return best?.restore
        }
    }
}

// MARK: - View modifier

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
