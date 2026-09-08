import XCTest

/// Drives the installed Diverge Sample against `banners_server.py` in both
/// conversation flows: patterned URL shows PDP banner, unmatched shows default,
/// CTA records via Sample `onOpenLink`, dismiss hides until relaunch, empty list
/// shows no strip.
final class BannerTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-banners"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!
    private let ctaURL = "http://127.0.0.1:3000/promo/sale"
    private let welcome = "Local stand-in — in-chat banners."
    private let patternedMessage = "Free shipping on PDP"
    private let defaultMessage = "Welcome offer — sitewide"

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)

        // 1. Patterned URL → Free shipping banner
        var status = try controlCall(["reset": true])
        print("EVIDENCE \(flow) server run=\(status["run"] ?? "?")")
        var app = launch(flow: flow, page: "https://shop.example.com/products/123")
        try waitUntilChatReady(app, flow: flow, message: patternedMessage)
        XCTAssertTrue(app.staticTexts[patternedMessage].exists)
        XCTAssertFalse(app.staticTexts[defaultMessage].exists, "default must stay hidden when pattern matches")
        shot(app, "\(flow)-10-patterned")
        print("EVIDENCE \(flow) patterned banner shown")

        // 2. CTA → sample.lastOpenedURL
        let cta = app.buttons["banner.cta.10"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "banner CTA missing")
        cta.tap()
        let opened = app.descendants(matching: .any)["sample.lastOpenedURL"].firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 8), "sample.lastOpenedURL missing after CTA")
        let openedText = (opened.label as String) + ((opened.value as? String) ?? "")
        XCTAssertTrue(
            openedText.contains(ctaURL)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", ctaURL)).firstMatch.exists,
            "CTA should open \(ctaURL); got \(openedText)"
        )
        shot(app, "\(flow)-11-cta")
        print("EVIDENCE \(flow) CTA opened \(ctaURL)")

        // 3. Dismiss hides until relaunch
        let dismiss = app.buttons["banner.dismiss.10"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), "dismiss control missing")
        dismiss.tap()
        XCTAssertFalse(
            app.staticTexts[patternedMessage].waitForExistence(timeout: 2),
            "banner should hide after dismiss"
        )
        shot(app, "\(flow)-12-dismissed")
        print("EVIDENCE \(flow) dismiss hid banner")
        app.terminate()

        // Relaunch same page → banner returns (new AIChat / makeView)
        app = launch(flow: flow, page: "https://shop.example.com/products/123")
        try waitUntilChatReady(app, flow: flow, message: patternedMessage)
        XCTAssertTrue(app.staticTexts[patternedMessage].exists, "banner should return after relaunch")
        shot(app, "\(flow)-13-after-relaunch")
        print("EVIDENCE \(flow) relaunch restored banner")
        app.terminate()

        // 4. Unmatched URL → default banner
        _ = try controlCall(["reset": true])
        app = launch(flow: flow, page: "https://shop.example.com/cart")
        try waitUntilChatReady(app, flow: flow, message: defaultMessage)
        XCTAssertTrue(app.staticTexts[defaultMessage].exists)
        XCTAssertFalse(app.staticTexts[patternedMessage].exists)
        shot(app, "\(flow)-20-default")
        print("EVIDENCE \(flow) default fallback shown")
        app.terminate()

        // 5. Empty list → no strip
        _ = try controlCall(["reset": true, "banners_empty": true])
        app = launch(flow: flow, page: "https://shop.example.com/products/1")
        try waitUntilChatReady(app, flow: flow, message: nil)
        XCTAssertFalse(app.staticTexts[patternedMessage].exists)
        XCTAssertFalse(app.staticTexts[defaultMessage].exists)
        XCTAssertFalse(app.buttons["banner.cta.10"].exists)
        shot(app, "\(flow)-30-empty")
        print("EVIDENCE \(flow) empty list shows no banner")

        status = try controlCall([:])
        let hits = status["banner_hits"] as? [[String: Any]] ?? []
        XCTAssertFalse(hits.isEmpty, "stand-in should have recorded GET /banners")
        let auth = hits.last?["auth"] as? String ?? ""
        XCTAssertTrue(auth.hasPrefix("Bearer "), "banners must send Bearer; got \(auth)")
        print("EVIDENCE \(flow) GET /banners auth=\(auth) hits=\(hits.count)")
        print("EVIDENCE \(flow) done")
        app.terminate()
    }

    /// Wait for welcome chrome. When `message` is set, also wait for that banner body.
    private func waitUntilChatReady(_ app: XCUIApplication, flow: String, message: String?) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        var sawUnavailable = false
        while Date() < deadline {
            if unavailable.exists {
                sawUnavailable = true
                Thread.sleep(forTimeInterval: 0.4)
                continue
            }
            if app.staticTexts[welcome].exists {
                if let message {
                    if app.staticTexts[message].exists { return }
                } else {
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        shot(app, "\(flow)-fail-no-ready")
        if sawUnavailable || unavailable.exists {
            XCTFail("chat bootstrap failed — is banners_server.py listening on :3000?")
        } else {
            print("AX TREE:\n\(app.debugDescription)")
            XCTFail("chat never became ready (wanted banner message: \(message ?? "none"))")
        }
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
