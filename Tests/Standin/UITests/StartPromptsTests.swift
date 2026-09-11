import XCTest

/// Drives the installed Diverge Sample against `start_prompts_server.py` in both
/// conversation flows: chips under the welcome, tap sends and hides chips, reset
/// restores them, history with a user turn shows none, page filtering picks the
/// patterned chip over globals.
///
/// `{{quick_replies}}` is **not** stripped by the SDK. Device coverage is: leaked
/// history text does not become chips; a live SSE part that still contains the
/// marker is painted as stored. The converter strip is `parse-token.ts` (API
/// unit tests) — do not treat this UITest as proof that history is cleaned.
final class StartPromptsTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-start-prompts"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let run = try controlCall(["reset": true])["run"] as? String ?? "?"
        print("EVIDENCE \(flow) server run=\(run)")

        // 1. Welcome-only: global chip visible, patterned chips hidden (no SAMPLE_PAGE).
        var app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let track = app.buttons["startPrompt.0"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 10), "global start prompt missing")
        XCTAssertEqual(track.label, "Track my order")
        XCTAssertFalse(app.buttons["Find a size"].exists, "patterned chip must stay hidden without SAMPLE_PAGE")
        shot(app, "\(flow)-10-open-chips")
        print("EVIDENCE \(flow) welcome chips shown")

        // 2. Tap chip → sends, chips disappear, reply arrives.
        track.tap()
        XCTAssertTrue(app.staticTexts["Track my order"].waitForExistence(timeout: 10), "user echo missing")
        XCTAssertTrue(app.staticTexts["Noted: Track my order"].waitForExistence(timeout: 20), "reply missing")
        XCTAssertFalse(app.buttons["startPrompt.0"].waitForExistence(timeout: 2), "chips must hide after send")
        shot(app, "\(flow)-11-after-chip-send")
        print("EVIDENCE \(flow) chip send hid chips")

        // 3. Reset → chips return (Sample posts /__control only when SAMPLE_STANDIN=1).
        let reset = app.buttons["chat.reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "reset toolbar button missing")
        reset.tap()
        XCTAssertTrue(app.buttons["startPrompt.0"].waitForExistence(timeout: 15), "chips did not return after reset")
        shot(app, "\(flow)-12-after-reset")
        print("EVIDENCE \(flow) reset restored chips")
        app.terminate()

        // 4. Page filter: SAMPLE_PAGE=/products URL → "Find a size", not the global.
        app = launch(flow: flow, page: "https://shop.example.com/products/123")
        try waitUntilChatReady(app, flow: flow)
        let size = app.buttons.matching(NSPredicate(format: "label == 'Find a size'")).firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 10), "patterned chip missing for /products")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Track my order'")).firstMatch.exists,
                       "global must be suppressed when a pattern matches")
        shot(app, "\(flow)-13-page-filter")
        print("EVIDENCE \(flow) page filter picked patterned chip")
        app.terminate()

        // 5. History already has a user turn → no chips (plan verify list).
        _ = try controlCall(["reset": true, "seed_user_history": true])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow, readyHint: "hello from history")
        XCTAssertTrue(app.staticTexts["hello from history"].waitForExistence(timeout: 10), "seeded user turn missing")
        XCTAssertFalse(app.buttons["startPrompt.0"].exists, "chips must stay hidden when history has a user turn")
        shot(app, "\(flow)-14-history-user-turn")
        print("EVIDENCE \(flow) history with user turn hid chips")
        app.terminate()

        // 6. Persisted leak: SDK does not strip stored rich_text. Marker stays visible;
        // Dry/Oily are not chips. Converter strip is API-only.
        _ = try controlCall(["reset": true, "emit_quick_replies_leak": true])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'What next?'")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '{{quick_replies:'")).firstMatch.exists,
            "SDK must paint stored rich_text as-is; it does not strip the marker"
        )
        XCTAssertFalse(app.buttons["Dry"].exists)
        XCTAssertFalse(app.buttons["Oily"].exists)
        shot(app, "\(flow)-15-quick-replies-stored-as-text")
        print("EVIDENCE \(flow) stored quick_replies is text, not chips")
        app.terminate()

        // 7. Live SSE still containing the marker is also painted (documents that the
        // SDK does not strip on the client).
        _ = try controlCall(["reset": true, "live_quick_replies": true])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        app.buttons["startPrompt.0"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS '{{quick_replies:'")).firstMatch.waitForExistence(timeout: 20),
            "live part with a marker must still render as text"
        )
        XCTAssertFalse(app.buttons["Dry"].exists)
        shot(app, "\(flow)-16-live-quick-replies-painted")
        print("EVIDENCE \(flow) live quick_replies painted as stored")
        print("EVIDENCE \(flow) done")
        app.terminate()
    }

    private func waitUntilChatReady(_ app: XCUIApplication, flow: String, readyHint: String? = nil) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is start_prompts_server.py listening on :3000?")
                return
            }
            if let readyHint, app.staticTexts[readyHint].exists { return }
            if app.buttons["startPrompt.0"].exists || app.buttons["Find a size"].exists { return }
            if app.staticTexts["Tap a chip below, or say hello."].exists { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        shot(app, "\(flow)-fail-no-ready")
        print("AX TREE:\n\(app.debugDescription)")
        XCTFail("chat never became ready")
    }

    private func launch(flow: String, page: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launchEnvironment["SAMPLE_STANDIN"] = "1"
        if let page {
            app.launchEnvironment["SAMPLE_PAGE"] = page
        }
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

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
