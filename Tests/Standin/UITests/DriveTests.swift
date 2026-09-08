import XCTest

/// Drives the installed Diverge Sample against the local stand-in API and saves screenshots.
final class DriveTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots"

    func testAttachmentsAndTokenRotation() throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        // Record taps on signed URLs without leaving Sample for Safari.
        app.launchEnvironment["SAMPLE_STANDIN"] = "1"
        app.launch()

        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 20), "composer not found")
        sleep(2)
        shot(app, "05-open")

        // Turn 1 — unbound host token; done carries visitor_token.
        field.tap()
        field.typeText("Send me the photo")
        tapSend(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Reply #1'")).firstMatch
            .waitForExistence(timeout: 25), "reply #1 did not render")
        sleep(3)
        shot(app, "06-reply1")

        // Turn 2 — must go out with the adopted bound token.
        field.tap()
        field.typeText("And the PDF")
        tapSend(app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Reply #2'")).firstMatch
            .waitForExistence(timeout: 25), "reply #2 did not render")
        sleep(3)
        app.swipeUp()
        sleep(1)
        shot(app, "07-reply2")

        // Tap the newest image tile -> host opens the signed URL.
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Live photo #2'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "image tile not found")
        XCTAssertTrue(tile.isEnabled, "live tile should be enabled")
        tile.tap()
        sleep(4)
        shot(app, "08-after-image-tap")

        // Back to the sample and tap the file row.
        app.activate()
        sleep(2)
        let file = app.buttons.matching(NSPredicate(format: "label CONTAINS 'signed-2.pdf'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5), "file row not found")
        file.tap()
        sleep(4)
        shot(app, "09-after-file-tap")
        app.activate()
    }

    // MARK: - Helpers

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let byPlaceholder = app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.waitForExistence(timeout: 15) { return byPlaceholder }
        let asField = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if asField.exists { return asField }
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    /// The send button is the enabled button nearest the bottom-right corner.
    private func tapSend(_ app: XCUIApplication) {
        let screen = app.frame
        let candidates = app.buttons.allElementsBoundByIndex.filter {
            $0.isEnabled && $0.frame.midY > screen.height * 0.8 && $0.frame.midX > screen.width * 0.7
        }
        guard let send = candidates.max(by: { $0.frame.midX < $1.frame.midX }) else {
            XCTFail("send button not found"); return
        }
        send.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
