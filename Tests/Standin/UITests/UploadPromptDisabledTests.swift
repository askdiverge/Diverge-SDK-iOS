import XCTest

/// Host `attachments: .disabled` against `upload_prompt_server.py` with `SEED_MARKER_ONLY=1`.
/// Kept as its own class so the runner can start a fresh server without `TAIL_DELAY`.
final class UploadPromptDisabledTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-upload-prompt"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        StandinControl.reset()
    }

    /// Neither the card nor the composer attach button may exist, and the marker-only
    /// seeded message must not leave a row behind.
    func testDisabledAttachments() throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = "topDown"
        app.launchEnvironment["SAMPLE_ATTACHMENTS"] = "disabled"
        app.launch()

        XCTAssertTrue(composer(app).waitForExistence(timeout: 20), "composer not found")
        let seed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'receipt'")).firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 20), "seeded assistant text not rendered")
        sleep(2)

        // Server runs with SEED_MARKER_ONLY=1: a marker-only message sits between "receipt" and
        // the trailing note. Dropped at ingestion, the two texts must sit one row pitch apart.
        let trailing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Trailing note'")).firstMatch
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "trailing seeded text not rendered")
        let gap = trailing.frame.minY - seed.frame.maxY
        print("EVIDENCE disabled gap receipt→trailing=\(gap)pt")
        XCTAssertLessThan(gap, 70, "an empty row for the dropped marker-only message would widen the gap")

        XCTAssertFalse(uploadPrompt(app).exists, "upload prompt card rendered with attachments disabled")
        let attach = app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Attach a photo' OR label CONTAINS[c] 'input.attachPhoto'")).firstMatch
        XCTAssertFalse(attach.exists, "composer attach button rendered with attachments disabled")
        print("EVIDENCE disabled card=\(uploadPrompt(app).exists) attach=\(attach.exists)")
        shot(app, "disabled-10-open")
        app.terminate()
    }

    private func uploadPrompt(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Add a photo' OR label CONTAINS[c] 'imageUpload.prompt' OR label CONTAINS[c] 'photo so I can help'"
        )).firstMatch
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let byPlaceholder = app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.waitForExistence(timeout: 15) { return byPlaceholder }
        let asField = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if asField.exists { return asField }
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
