import XCTest
import UIKit

/// Drives the installed Diverge Sample against `export_server.py` in both conversation flows.
final class DownloadDataTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-download-data"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)

        // --- Happy path: row → GET /export with Bearer → share sheet; chat stays ---
        var status = try controlCall(["reset": true, "export_status": 200])
        print("EVIDENCE \(flow) server run=\(status["run"] ?? "?")")
        var app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)

        openPrivacy(app)
        let download = app.descendants(matching: .any)["privacy.download"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 5), "privacy.download missing")
        shot(app, "\(flow)-10-privacy-menu")
        download.tap()

        // Share / activity sheet (Copy, Save to Files, …) or the file name in the sheet.
        let shareAppeared = waitForShareSheet(app, timeout: 8)
        XCTAssertTrue(shareAppeared, "share sheet should appear after export")
        shot(app, "\(flow)-11-share-sheet")
        print("EVIDENCE \(flow) share sheet after successful export")

        // Dismiss share sheet and privacy sheet; conversation must still be alive.
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.5)
        if app.staticTexts["Privacy & Data"].exists {
            app.swipeDown()
        }
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(
            app.staticTexts["Local stand-in — download my data."].waitForExistence(timeout: 5),
            "conversation should still be on screen (token not dropped)"
        )
        status = try controlCall([:])
        let hits = status["export_hits"] as? [[String: Any]] ?? []
        XCTAssertFalse(hits.isEmpty, "stand-in should have recorded GET /export")
        let auth = hits.last?["auth"] as? String ?? ""
        XCTAssertTrue(auth.hasPrefix("Bearer "), "export must send Bearer; got \(auth)")
        print("EVIDENCE \(flow) GET /export auth=\(auth)")
        app.terminate()

        // --- Injected 500 → inline error, sheet stays ---
        _ = try controlCall(["reset": true, "export_status": 500])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        openPrivacy(app)
        app.descendants(matching: .any)["privacy.download"].firstMatch.tap()
        let error = app.descendants(matching: .any)["privacy.downloadError"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 8), "inline export error missing")
        XCTAssertTrue(app.staticTexts["Privacy & Data"].exists, "privacy sheet should stay open")
        shot(app, "\(flow)-20-export-error")
        print("EVIDENCE \(flow) 500 → inline error")
        app.terminate()

        // --- Injected 401 → session-ended alert ---
        _ = try controlCall(["reset": true, "export_status": 401])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        openPrivacy(app)
        app.descendants(matching: .any)["privacy.download"].firstMatch.tap()
        let ended = app.alerts.firstMatch
        XCTAssertTrue(ended.waitForExistence(timeout: 8), "session-ended alert missing after 401")
        shot(app, "\(flow)-30-session-ended")
        print("EVIDENCE \(flow) 401 → session-ended alert")
        app.terminate()

        // --- Dismiss Privacy mid-GET: reopen must not auto-present share ---
        try runDismissDuringExport(flow: flow)
        print("EVIDENCE \(flow) done")
    }

    /// Share sheet on iPad (popover source). Skips on iPhone destinations.
    func testIPadShareSheet() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "boot an iPad simulator to run the popover share-sheet check"
        )
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        _ = try controlCall(["reset": true, "export_status": 200, "export_delay_ms": 0])
        let app = launch(flow: "topDown")
        try waitUntilChatReady(app, flow: "iPad")
        openPrivacy(app)
        app.descendants(matching: .any)["privacy.download"].firstMatch.tap()
        XCTAssertTrue(waitForShareSheet(app, timeout: 8), "iPad share popover/sheet should appear without crashing")
        shot(app, "ipad-share-sheet")
        print("EVIDENCE iPad share sheet presented")
        app.terminate()
    }

    private func runDismissDuringExport(flow: String) throws {
        _ = try controlCall(["reset": true, "export_status": 200, "export_delay_ms": 2500])
        let app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        openPrivacy(app)
        app.descendants(matching: .any)["privacy.download"].firstMatch.tap()
        // Dismiss Privacy while the stand-in is still sleeping on GET /export.
        Thread.sleep(forTimeInterval: 0.35)
        dismissPrivacy(app)
        shot(app, "\(flow)-40-dismissed-mid-export")
        XCTAssertFalse(
            app.staticTexts["Privacy & Data"].exists,
            "Privacy should be gone after swipe-dismiss mid-export"
        )

        Thread.sleep(forTimeInterval: 2.8)
        XCTAssertFalse(
            shareSheetVisible(app),
            "share must not appear after Privacy was dismissed mid-GET"
        )

        let hitsBeforeReopen = (try controlCall([:])["export_hits"] as? [[String: Any]])?.count ?? 0
        openPrivacy(app)
        XCTAssertTrue(app.staticTexts["Privacy & Data"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            waitForShareSheet(app, timeout: 1.5, logOnTimeout: false),
            "reopening Privacy must not auto-present the leftover share sheet"
        )
        Thread.sleep(forTimeInterval: 0.4)
        let hitsAfterReopen = (try controlCall([:])["export_hits"] as? [[String: Any]])?.count ?? 0
        XCTAssertEqual(
            hitsBeforeReopen,
            hitsAfterReopen,
            "reopen alone must not fire a second GET /export (hits \(hitsBeforeReopen) → \(hitsAfterReopen))"
        )
        shot(app, "\(flow)-41-reopen-no-share")
        print("EVIDENCE \(flow) dismiss mid-GET → no auto share; hits=\(hitsAfterReopen)")
        app.terminate()
    }

    private func openPrivacy(_ app: XCUIApplication) {
        let open = app.buttons["privacy.open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "privacy.open missing")
        open.tap()
        XCTAssertTrue(app.staticTexts["Privacy & Data"].waitForExistence(timeout: 5))
    }

    private func dismissPrivacy(_ app: XCUIApplication) {
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.4)
        if app.staticTexts["Privacy & Data"].exists {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func shareSheetVisible(_ app: XCUIApplication) -> Bool {
        if app.otherElements["ActivityListView"].exists { return true }
        if app.collectionViews["ActivityListView"].exists { return true }
        if app.buttons["Copy"].exists { return true }
        if app.buttons["Save to Files"].exists { return true }
        if app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'diverge-export'")).firstMatch.exists {
            return true
        }
        if app.popovers.firstMatch.exists { return true }
        if app.otherElements.matching(NSPredicate(format: "identifier CONTAINS[c] 'Activity'")).firstMatch.exists {
            return true
        }
        return false
    }

    private func waitForShareSheet(
        _ app: XCUIApplication,
        timeout: TimeInterval,
        logOnTimeout: Bool = true
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if shareSheetVisible(app) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if logOnTimeout {
            print("AX TREE (no share):\n\(app.debugDescription)")
        }
        return false
    }

    private func waitUntilChatReady(_ app: XCUIApplication, flow: String) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is export_server.py listening on :3000?")
                return
            }
            if app.staticTexts["Local stand-in — download my data."].exists { return }
            if app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch.exists {
                return
            }
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
