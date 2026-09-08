import XCTest

/// Drives the installed Diverge Sample against the rating stand-in (`rating_server.py`) in both
/// conversation flows.
///
/// Scale Skip and a backdrop tap send nothing. Feedback Skip POSTs the numeric score with no
/// written feedback. Sample reuses `AIChat` across Open chat, so a second close after a
/// successful rating does not re-ask (no `app.launch()` between those two presents).
///
/// The harness lives under `/tmp` with the other stand-in tests; promote with them later.
final class RatingTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-rating"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let run = try controlCall(["reset": true])["run"] as? String ?? "?"
        print("EVIDENCE \(flow) server run=\(run)")

        // 1. Open with only the welcome — close should skip the rating overlay.
        var app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        shot(app, "\(flow)-10-open")
        let close1 = closeButton(app)
        print("EVIDENCE close1 exists=\(close1.exists) hittable=\(close1.isHittable) label=\(close1.label)")
        close1.tap()
        XCTAssertFalse(app.staticTexts["How good was the chatbot?"].waitForExistence(timeout: 2),
                       "rating overlay must not appear without a user turn")
        print("EVIDENCE \(flow) close-without-chat skipped rating")

        // 2. Re-open, send a message, rate 5 — overlay appears, submits, dismisses.
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        send(app, "hello")
        XCTAssertTrue(app.staticTexts["Noted."].waitForExistence(timeout: 20), "reply missing")
        XCTAssertFalse(app.staticTexts["Something went wrong, try again"].waitForExistence(timeout: 1))
        shot(app, "\(flow)-11-after-send")
        let close2 = closeButton(app)
        print("EVIDENCE close2 exists=\(close2.exists) hittable=\(close2.isHittable) label=\(close2.label)")
        close2.tap()
        let title = app.staticTexts["How good was the chatbot?"]
        let score5 = app.buttons["rating.score.5"].firstMatch
        XCTAssertTrue(
            title.waitForExistence(timeout: 10) || score5.waitForExistence(timeout: 2),
            "rating overlay did not appear"
        )
        shot(app, "\(flow)-12-rating-sheet")
        app.buttons["rating.score.5"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Open chat"].waitForExistence(timeout: 15)
                      || app.staticTexts["Diverge Sample"].waitForExistence(timeout: 5),
                      "Sample did not reappear after rating 5")
        print("EVIDENCE \(flow) rated 5 and closed")
        shot(app, "\(flow)-13-after-rate-5")

        // 2b. Same Sample process, same AIChat — Open chat again, close, no re-ask.
        app.buttons["Open chat"].firstMatch.tap()
        try waitUntilChatReady(app, flow: flow)
        closeButton(app).tap()
        XCTAssertFalse(title.waitForExistence(timeout: 2),
                       "\(flow): second close on the same AIChat must not re-ask")
        XCTAssertTrue(app.buttons["Open chat"].waitForExistence(timeout: 10)
                      || app.staticTexts["Diverge Sample"].waitForExistence(timeout: 5))
        print("EVIDENCE \(flow) same-session second close did not re-ask")

        // 3. Scale Skip — no POST.
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        send(app, "scale skip")
        XCTAssertTrue(app.staticTexts["Noted."].waitForExistence(timeout: 20))
        let beforeScaleSkip = try ratingsCount()
        closeButton(app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.buttons["rating.skip"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Diverge Sample"].waitForExistence(timeout: 15)
                      || app.buttons["Open chat"].waitForExistence(timeout: 5))
        XCTAssertEqual(try ratingsCount(), beforeScaleSkip, "\(flow): scale Skip must not POST /rate")
        print("EVIDENCE \(flow) scale Skip sent no rate")

        // 4. Feedback Skip — POSTs the score with no written feedback.
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        send(app, "need help")
        XCTAssertTrue(app.staticTexts["Noted."].waitForExistence(timeout: 20))
        let beforeFeedbackSkip = try ratingsCount()
        closeButton(app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.buttons["rating.score.2"].firstMatch.tap()
        let feedback = app.textFields["rating.feedback"].firstMatch.exists
            ? app.textFields["rating.feedback"].firstMatch
            : app.textViews["rating.feedback"].firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "feedback field missing for score 2")
        shot(app, "\(flow)-14-feedback-step")
        app.buttons["rating.skip"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Diverge Sample"].waitForExistence(timeout: 15)
                      || app.buttons["Open chat"].waitForExistence(timeout: 5))
        let afterFeedbackSkip = try peek()
        XCTAssertEqual(afterFeedbackSkip["count"] as? Int, beforeFeedbackSkip + 1,
                       "\(flow): feedback Skip must POST /rate")
        let last = afterFeedbackSkip["last"] as? [String: Any]
        XCTAssertEqual(last?["rating"] as? Int, 2, "\(flow): feedback Skip must send score 2")
        XCTAssertTrue(last?["feedback"] == nil || last?["feedback"] is NSNull,
                      "\(flow): feedback Skip must omit written feedback")
        print("EVIDENCE \(flow) feedback Skip posted rating 2 with no feedback")

        // 5. Injected 500 → overlay stays with error; re-tap the same score succeeds.
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        send(app, "retry please")
        XCTAssertTrue(app.staticTexts["Noted."].waitForExistence(timeout: 20))
        _ = try controlCall(["fail_next_rate": true])
        closeButton(app).tap()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.buttons["rating.score.4"].firstMatch.tap()
        let error = app.staticTexts["Couldn't send your rating. Try again."]
        XCTAssertTrue(error.waitForExistence(timeout: 15), "500 did not surface on the overlay")
        shot(app, "\(flow)-15-rate-500")
        app.buttons["rating.score.4"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Diverge Sample"].waitForExistence(timeout: 15)
                      || app.buttons["Open chat"].waitForExistence(timeout: 5),
                      "retry after 500 did not close")
        print("EVIDENCE \(flow) 500 surfaced then retry landed")
        shot(app, "\(flow)-16-retry-ok")

        print("EVIDENCE \(flow) done")
        app.terminate()
    }

    /// Wait until the chat is ready (composer + close). Fail loudly on the bootstrap error screen
    /// instead of matching a stray text field.
    private func waitUntilChatReady(_ app: XCUIApplication, flow: String) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let composerReady = composer(app)
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is rating_server.py listening on :3000?")
                return
            }
            if composerReady.waitForExistence(timeout: 1) { break }
        }
        if !composerReady.exists {
            shot(app, "\(flow)-fail-no-composer")
            print("AX TREE:\n\(app.debugDescription)")
        }
        XCTAssertTrue(composerReady.exists, "composer not found (placeholder 'Ask anything')")
        let close = closeButton(app)
        if !close.waitForExistence(timeout: 8) {
            shot(app, "\(flow)-fail-no-close")
            print("AX TREE:\n\(app.debugDescription)")
        }
        XCTAssertTrue(close.exists,
                      "close button missing — Sample must pass onClose and chat must be .ready")
    }

    // MARK: - Helpers

    private func closeButton(_ app: XCUIApplication) -> XCUIElement {
        let byId = app.descendants(matching: .any).matching(identifier: "rating.close").firstMatch
        if byId.exists { return byId }
        return app.buttons["Close"].firstMatch
    }

    private func launch(flow: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launch()
        return app
    }

    @discardableResult
    private func controlCall(_ body: [String: Any]) throws -> [String: Any] {
        var request = URLRequest(url: control)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let done = expectation(description: "control")
        var result: [String: Any] = [:]
        URLSession.shared.dataTask(with: request) { data, _, _ in
            result = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        return result
    }

    private func peek() throws -> [String: Any] {
        try controlCall(["peek": true])
    }

    private func ratingsCount() throws -> Int {
        try peek()["count"] as? Int ?? 0
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let field = composer(app)
        field.tap()
        field.typeText(text)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) { notNow.tap() }
        let sendButton = app.buttons.matching(NSPredicate(format: "label == 'Up'")).firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "send button not found")
        sendButton.tap()
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let byPlaceholder = app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.exists { return byPlaceholder }
        return app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
