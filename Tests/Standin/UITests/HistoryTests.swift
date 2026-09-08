import XCTest

/// Drives the installed Diverge Sample against the local history stand-in (history_server.py) and
/// measures the scroll-up pagination: trigger, spinner, hop at the boundary, retry, exhaustion,
/// and a send after prepends. Prints `EVIDENCE` lines; screenshots go to /tmp/diverge-standin/shots-history.
final class HistoryTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-history"

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launch()

        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 20), "composer not found")
        XCTAssertTrue(row(app, 299).waitForExistence(timeout: 20), "newest seeded message not rendered")
        sleep(2)
        shot(app, "\(flow)-00-open")
        XCTAssertFalse(row(app, 199).exists, "page 2 must not be loaded before scrolling")
        assertRenderOrder(app, flow: flow, tag: "open")

        // Page 1 → page 2 (DELAY holds the fetch so the window is observable).
        let hop1 = try loadOlderPage(app, flow: flow, tag: "p2", oldestLoaded: 200, expectNext: 199)
        print("EVIDENCE \(flow) hop at page-2 boundary: \(hop1)")
        XCTAssertEqual(hop1, 0, accuracy: 2, "p2: the reader moved across the prepend")

        // Page 2 → page 3; the server answers 500 first (FAIL_ONCE=c2): no jump, notice, then retry.
        let hop2 = try loadOlderPage(app, flow: flow, tag: "p3", oldestLoaded: 100, expectNext: 99)
        print("EVIDENCE \(flow) hop at page-3 boundary (after retry): \(hop2)")
        XCTAssertEqual(hop2, 0, accuracy: 2, "p3: the reader moved across the prepend")

        // Exhausted: reach #000, no spinner appears, and the server is not asked again. The chat is a
        // sheet, so once the list is at its top a further full swipe would dismiss it — drag gently.
        let callsBefore = historyCallCount()
        XCTAssertTrue(scrollUntilVisible(app, row(app, 0), maxSwipes: 60), "could not reach the oldest message")
        sleep(1)
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        mid.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        sleep(1)
        XCTAssertFalse(spinner(app).exists, "spinner must not show once history is exhausted")
        XCTAssertEqual(historyCallCount(), callsBefore, "server must not be asked once history is exhausted")
        shot(app, "\(flow)-30-exhausted-top")
        let oldest = row(app, 0)
        XCTAssertTrue(oldest.exists, "oldest message must be on screen")
        print("EVIDENCE \(flow) oldest row visible=\(oldest.exists) frame=\(oldest.exists ? "\(oldest.frame)" : "-"); topmost=\(topmostVisibleRow(app)); history calls=\(historyCallCount())")
        assertRenderOrder(app, flow: flow, tag: "exhausted-top")

        // A send after two prepends still behaves: reply streams in.
        field.tap()
        sleep(1)
        field.typeText("after two prepends")
        tapSend(app)
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Reply #1'")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "reply after prepends did not render")
        sleep(2)
        shot(app, "\(flow)-40-after-send")
        let sent = app.staticTexts.matching(NSPredicate(format: "label == 'after two prepends'")).firstMatch
        print("EVIDENCE \(flow) sent turn frame: \(sent.frame) reply frame: \(reply.frame) screen: \(app.frame)")
        if flow == "topDown" {
            // The lifted exchange: the sent turn sits at the top of the list and the reply directly under it,
            // the buffer (sized from the per-turn heights) taking the rest — no dead space between the two.
            XCTAssertLessThan(sent.frame.minY, app.frame.height * 0.35, "topDown: the sent turn was not lifted to the top")
            XCTAssertGreaterThan(reply.frame.minY, sent.frame.maxY, "topDown: the reply is not beneath the sent turn")
            XCTAssertLessThan(reply.frame.minY - sent.frame.maxY, 80, "topDown: dead space between the sent turn and the reply")
        }
        app.terminate()
    }

    /// Scrolls up until `oldestLoaded` (the current first turn) is on screen, then waits for the page
    /// above it. Returns the vertical hop of the topmost visible seeded row across the prepend.
    private func loadOlderPage(_ app: XCUIApplication, flow: String, tag: String, oldestLoaded: Int, expectNext: Int) throws -> CGFloat {
        // Swipe up until the near-top trigger fires (spinner appears); DELAY on the server keeps the
        // page from landing for a few seconds so the reader's position can be sampled in between.
        // The server writes a "start" evidence line the moment an older-page request arrives and a
        // status line when it answers — the load's lifetime is read from there, not from the spinner.
        let startsBefore = historyStarts()
        let completionsBefore = historyCallCount()
        var triggered = false
        for _ in 0..<60 where !triggered {
            app.swipeDown(velocity: .fast)
            let deadline = Date().addingTimeInterval(0.4)
            while Date() < deadline, !triggered { triggered = historyStarts() > startsBefore; usleep(50_000) }
        }
        XCTAssertTrue(triggered, "\(tag): no older-page request while scrolling toward #\(oldestLoaded)")
        let startedAt = evidence().last { $0["phase"] as? String == "start" }?["t"] as? Double ?? 0
        print("EVIDENCE \(flow) \(tag): request seen \(String(format: "%.2f", Date().timeIntervalSince1970 - startedAt))s after it reached the server")
        usleep(700_000) // let deceleration end
        let (label, before) = topmostVisibleRow(app)
        let visibleBefore = visibleRowLabels(app)
        shot(app, "\(flow)-\(tag)-10-before")
        print("EVIDENCE \(flow) \(tag): trigger fired; topmost visible=\(label) at \(before); visible rows=\(visibleBefore); spinner=\(spinner(app).exists)")

        // The fetch settles when the server answers; the evidence says whether it was a 200 or the
        // injected 500 (a row of the new page may be off screen, so "row exists" is not a landing signal).
        XCTAssertTrue(waitForHistoryCompletions(above: completionsBefore, timeout: 15), "\(tag): the request never completed")
        sleep(1)
        XCTAssertFalse(spinner(app).exists, "\(tag): spinner still showing after the request completed")
        var status = lastHistoryStatus()
        var (labelAfter, after) = frame(of: label, in: app)
        print("EVIDENCE \(flow) \(tag): fetch settled with status=\(status); \(label) now at \(after) (\(labelAfter)); visible rows=\(visibleRowLabels(app))")
        if status == 500 {
            // Retry path: the injected 500 shows a notice and arms the cooldown; the reader must not move,
            // and scrolling further up afterwards must retry.
            let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'older messages'")).firstMatch
            let retryButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Retry'")).firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 2), "\(tag): inline failure message not shown")
            XCTAssertTrue(retryButton.exists, "\(tag): inline retry button not shown")
            print("EVIDENCE \(flow) \(tag): failed load — inline bar message=\(message.exists ? message.label : "-") retry=\(retryButton.exists) frame=\(retryButton.frame)")
            XCTAssertEqual(after.minY, before.minY, accuracy: 1, "\(tag): a failed load must not move the reader")
            shot(app, "\(flow)-\(tag)-15-failed")
            // topDown retries through the inline button (at once, no cooldown); bottomUp by scrolling
            // further up after the cooldown — both paths must land the page.
            var retried = false
            let retryStartsBefore = historyStarts()
            if flow == "topDown" {
                retryButton.tap()
                retried = waitForHistoryStarts(above: retryStartsBefore, timeout: 2)
            } else {
                sleep(2) // cooldown
                // The trigger is level-triggered: any scroll while still within one viewport of the top
                // retries. At the very top of a sheet a swipe *down* drags the sheet, not the list, so
                // nudge the list first (the nudge itself is a scroll near the top and retries).
                app.swipeUp(velocity: .slow)
                retried = waitForHistoryStarts(above: retryStartsBefore, timeout: 1)
                for _ in 0..<5 where !retried {
                    app.swipeDown(velocity: .slow)
                    retried = waitForHistoryStarts(above: retryStartsBefore, timeout: 1)
                }
            }
            XCTAssertTrue(retried, "\(tag): retry did not start a load")
            XCTAssertFalse(retryButton.exists, "\(tag): retry bar must go once the retry starts")
            usleep(700_000)
            let (labelRetry, beforeRetry) = topmostVisibleRow(app)
            let spinnerDuringRetry = spinner(app).exists
            XCTAssertTrue(waitForHistoryCompletions(above: historyCallCount(), timeout: 15), "\(tag): the retry never completed")
            sleep(1)
            status = lastHistoryStatus()
            (labelAfter, after) = frame(of: labelRetry, in: app)
            print("EVIDENCE \(flow) \(tag): retry — spinner=\(spinnerDuringRetry) status=\(status); \(labelRetry) was at \(beforeRetry) now at \(after) (\(labelAfter)); visible rows=\(visibleRowLabels(app))")
            shot(app, "\(flow)-\(tag)-20-after")
            XCTAssertEqual(status, 200, "\(tag): retry did not land the page")
            assertRenderOrder(app, flow: flow, tag: "\(tag)-landed")
            assertBoundaryOrder(app, flow: flow, tag: tag, oldestLoaded: oldestLoaded)
            return after.isNull ? .nan : after.minY - beforeRetry.minY
        }
        XCTAssertEqual(status, 200, "\(tag): page did not land")
        shot(app, "\(flow)-\(tag)-20-after")
        XCTAssertFalse(after.isNull, "\(tag): the row that was on screen before the prepend (\(label)) is gone — the reader was moved")
        assertRenderOrder(app, flow: flow, tag: "\(tag)-landed")
        assertBoundaryOrder(app, flow: flow, tag: tag, oldestLoaded: oldestLoaded)
        return after.isNull ? .nan : after.minY - before.minY
    }

    /// Scrolls the old/new page boundary into view and checks the rows either side of it — the last
    /// prepended turn (`oldestLoaded - 1`) directly above the first previously loaded one.
    private func assertBoundaryOrder(_ app: XCUIApplication, flow: String, tag: String, oldestLoaded: Int) {
        let below = row(app, oldestLoaded)
        let above = row(app, oldestLoaded - 1)
        // The boundary sits just above where the reader was left, so nudge the content down (revealing
        // older rows) until both are on screen; back up only if the lower row has slid past mid-screen.
        for _ in 0..<8 where !(fullyVisible(above, in: app) && fullyVisible(below, in: app)) {
            let overshot = fullyVisible(below, in: app) && below.frame.minY > app.frame.height * 0.55
            let dir: CGFloat = overshot ? -0.12 : 0.12
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + dir)))
            usleep(700_000)
        }
        guard fullyVisible(above, in: app), fullyVisible(below, in: app) else {
            print("EVIDENCE \(flow) \(tag): boundary rows not both on screen (above=\(above.exists) below=\(below.exists)); order checked from the visible window instead")
            assertRenderOrder(app, flow: flow, tag: "\(tag)-boundary")
            return
        }
        XCTAssertLessThan(above.frame.maxY, below.frame.minY, "\(tag): #\(oldestLoaded - 1) must sit directly above #\(oldestLoaded)")
        assertRenderOrder(app, flow: flow, tag: "\(tag)-boundary")
    }

    private func fullyVisible(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && element.frame.minY >= 0 && element.frame.maxY <= app.frame.height
    }

    private func waitForSpinnerToDisappear(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !spinner(app).exists { return true }
            usleep(200_000)
        }
        return false
    }

    /// Status of the most recent history call the stand-in logged.
    private func lastHistoryStatus() -> Int {
        evidence().last { $0["status"] != nil }?["status"] as? Int ?? -1
    }

    private func frame(of label: String, in app: XCUIApplication) -> (String, CGRect) {
        let match = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        return match.exists ? (label, match.frame) : ("gone", .null)
    }

    /// The seed's role sequence, written by the stand-in as the first evidence line (SHAPE env).
    private func seedShape() -> [String] {
        evidence().first?["shape"] as? [String] ?? ["user", "assistant"]
    }

    /// Every fully visible seeded row must (a) run consecutively top → bottom and (b) carry the role the
    /// seed gave that index. Together that shows the wire order survived the prepend, not just the count.
    /// Which side a row renders on is not observable here — the text element's frame spans the full row
    /// width — so bubble alignment is read from the screenshots instead.
    private func assertRenderOrder(_ app: XCUIApplication, flow: String, tag: String) {
        let shape = seedShape()
        let rows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#'")).allElementsBoundByIndex
            .filter { $0.frame.minY >= 0 && $0.frame.maxY <= app.frame.height && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
        let parsed: [(n: Int, role: String)] = rows.compactMap { row in
            let words = row.label.split(separator: " ")
            guard words.count >= 2, let n = Int(words[0].dropFirst()) else { return nil }
            return (n, String(words[1]))
        }
        XCTAssertGreaterThan(parsed.count, 1, "\(tag): fewer than two seeded rows visible")
        let numbers = parsed.map(\.n)
        XCTAssertEqual(numbers, Array(numbers.first!...numbers.last!), "\(tag): visible rows are not consecutive top → bottom")
        for row in parsed {
            let expected = shape[row.n % shape.count]
            XCTAssertEqual(row.role, expected, "\(tag): #\(row.n) rendered as \(row.role), seed says \(expected)")
        }
        print("EVIDENCE \(flow) \(tag): render order \(parsed.map { "#\($0.n) \($0.role)" }) matches seed shape \(shape)")
    }

    private func visibleRowLabels(_ app: XCUIApplication) -> [String] {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#'")).allElementsBoundByIndex
            .filter { $0.frame.minY >= 0 && $0.frame.maxY <= app.frame.height && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
            .map { String($0.label.prefix(4)) }
    }

    // MARK: - Helpers

    private func row(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", String(format: "#%03d ", n))).firstMatch
    }

    private func spinner(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Loading earlier messages'")).firstMatch
    }

    /// The seeded row nearest the top of the screen that is fully on screen.
    private func topmostVisibleRow(_ app: XCUIApplication) -> (String, CGRect) {
        let rows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '#'")).allElementsBoundByIndex
            .filter { $0.frame.minY >= 0 && $0.frame.maxY <= app.frame.height && $0.frame.height > 0 }
            .sorted { $0.frame.minY < $1.frame.minY }
        guard let top = rows.first else { return ("-", .null) }
        return (String(top.label.prefix(4)), top.frame)
    }

    private func evidence() -> [[String: Any]] {
        guard let text = try? String(contentsOfFile: "/tmp/diverge-standin/history-evidence.jsonl", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            line.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    /// Completed history calls (a status line each).
    private func historyCallCount() -> Int { evidence().filter { $0["status"] != nil }.count }

    /// Older-page requests that have arrived at the server (answered or not).
    private func historyStarts() -> Int { evidence().filter { $0["phase"] as? String == "start" }.count }

    private func waitForHistoryStarts(above count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if historyStarts() > count { return true }
            usleep(100_000)
        }
        return false
    }

    private func waitForHistoryCompletions(above count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if historyCallCount() > count { return true }
            usleep(200_000)
        }
        return false
    }

    /// Fast swipes until `element` is fully on screen; the wait after each swipe lets the deceleration
    /// finish so a row that is about to arrive is seen before the next swipe (which, at the list's top,
    /// would pull the sheet down instead).
    private func scrollUntilVisible(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.frame.minY > 0 && element.frame.maxY < app.frame.height { return true }
            app.swipeDown(velocity: .fast)
            usleep(900_000)
        }
        return element.exists
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let byPlaceholder = app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.waitForExistence(timeout: 15) { return byPlaceholder }
        let asField = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if asField.exists { return asField }
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    private func tapSend(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) { notNow.tap() }
        let send = app.buttons.matching(NSPredicate(format: "label == 'Up'")).firstMatch
        guard send.waitForExistence(timeout: 5) else { XCTFail("send button not found"); return }
        send.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
