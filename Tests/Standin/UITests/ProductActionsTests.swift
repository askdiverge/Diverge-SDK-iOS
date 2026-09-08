import XCTest

/// Drives the installed Diverge Sample against `product_actions_server.py` in both
/// conversation flows: config open CTA label + localised fallback, product open via
/// `onOpenLink`, add-to-cart gate + sku report (per-card: only cards with a sku), splash
/// in the a11y label. Converter strip of `{{add_to_cart:…}}` is API-layer (unit tests),
/// not a device assertion.
final class ProductActionsTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-product-actions"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!
    private let productURL = "http://127.0.0.1:3000/products/classic-tee"

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let run = try controlCall([
            "reset": true,
            "open_label": "Se produkt",
            "add_to_cart_enabled": true,
        ])["run"] as? String ?? "?"
        print("EVIDENCE \(flow) server run=\(run)")

        var app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let open = app.buttons["product.0"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15), "product.0 missing")
        XCTAssertEqual(open.value as? String, "Se produkt", "CTA value should be config open_label")
        XCTAssertTrue(
            (open.label as String).contains("60% Deal"),
            "splash must be part of the accessibility label: \(open.label)"
        )
        XCTAssertTrue(
            (open.label as String).contains("Soft cotton"),
            "structured card description is painted verbatim: \(open.label)"
        )
        var cart = app.buttons["product.addToCart.0"].firstMatch
        XCTAssertTrue(cart.waitForExistence(timeout: 5), "add-to-cart must show when config+host allow")
        XCTAssertEqual(cart.label, "Add to cart")
        XCTAssertTrue(app.buttons["product.1"].waitForExistence(timeout: 5), "second card missing")
        XCTAssertFalse(
            app.buttons["product.addToCart.1"].exists,
            "card without sku must not show add-to-cart"
        )
        shot(app, "\(flow)-10-open-cta-and-cart")
        print("EVIDENCE \(flow) config CTA + cart shown")

        // Cart first (before open) while the initial layout is stable; scroll until truly above the composer.
        reveal(cart, in: app)
        // Prefer a mid-button coordinate tap — isHittable is flaky when the composer
        // overlaps the button's accessibility frame even after a scroll.
        cart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let added = app.descendants(matching: .any)["sample.lastAddedProduct"].firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "sample.lastAddedProduct missing after cart tap")
        let addedText = "\(added.label)\(added.value as? String ?? "")"
        XCTAssertTrue(addedText.contains("Classic Tee"), "title missing in \(addedText)")
        XCTAssertTrue(addedText.contains("SKU-TEE-001"), "sku missing in \(addedText)")
        shot(app, "\(flow)-11-after-cart")
        print("EVIDENCE \(flow) cart reported sku")

        open.tap()
        let opened = app.descendants(matching: .any)["sample.lastOpenedURL"].firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 10), "sample.lastOpenedURL missing after open tap")
        let openedBlob = "\(opened.label)\(opened.value as? String ?? "")"
        XCTAssertTrue(
            openedBlob.contains(productURL)
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", productURL)).firstMatch.exists,
            "opened URL should be \(productURL); got \(openedBlob)"
        )
        shot(app, "\(flow)-12-after-open")
        print("EVIDENCE \(flow) open reported URL")
        app.terminate()

        _ = try controlCall([
            "reset": true,
            "open_label": NSNull(),
            "add_to_cart_enabled": true,
        ])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let openFallback = app.buttons["product.0"].firstMatch
        XCTAssertTrue(openFallback.waitForExistence(timeout: 15))
        XCTAssertEqual(openFallback.value as? String, "View product", "null open_label must fall back to L10n")
        shot(app, "\(flow)-13-fallback-label")
        print("EVIDENCE \(flow) null label fell back to View product")
        app.terminate()

        _ = try controlCall([
            "reset": true,
            "open_label": "Se produkt",
            "add_to_cart_enabled": false,
        ])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        XCTAssertTrue(app.buttons["product.0"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["product.addToCart.0"].exists, "cart button must hide when config disables")
        shot(app, "\(flow)-14-cart-disabled")
        print("EVIDENCE \(flow) cart gated off by config")
        print("EVIDENCE \(flow) done")
        app.terminate()
    }

    /// Drag until the element sits above the composer band (~bottom 20% of the screen).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            guard element.exists else { return }
            let frame = element.frame
            if element.isHittable && frame.height > 8 && frame.maxY < app.frame.height * 0.78 {
                return
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.35)
        }
    }

    private func waitUntilChatReady(_ app: XCUIApplication, flow: String) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is product_actions_server.py listening on :3000?")
                return
            }
            if app.buttons["product.0"].exists { return }
            if app.staticTexts["Here are a couple of picks."].exists { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        shot(app, "\(flow)-fail-no-ready")
        print("AX TREE:\n\(app.debugDescription)")
        XCTFail("chat never became ready")
    }

    private func launch(flow: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launchEnvironment["SAMPLE_STANDIN"] = "1"
        app.launch()
        return app
    }

    @discardableResult
    private func controlCall(_ body: [String: Any]) throws -> [String: Any] {
        var request = URLRequest(url: control)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
