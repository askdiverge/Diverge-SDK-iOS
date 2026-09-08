import XCTest

/// Drives the installed Diverge Sample against the local send-photo stand-in and saves screenshots.
final class PhotoTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-photo"

    func testSendPhotoEchoAndHistory() throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launch()

        let field = composer(app)
        XCTAssertTrue(field.waitForExistence(timeout: 20), "composer not found")
        sleep(2)
        shot(app, "10-open")

        // Attach control present (host default .photoLibrary), enabled, labelled.
        let attach = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'attach' OR identifier CONTAINS[c] 'attach'")).firstMatch
        if !attach.waitForExistence(timeout: 5) {
            print("EVIDENCE composer tree: \(app.descendants(matching: .any).allElementsBoundByIndex.filter { $0.frame.minY > app.frame.height * 0.8 }.map { "\($0.elementType.rawValue):\($0.label)|\($0.identifier)" })")
            XCTFail("attach control not found")
        }
        print("EVIDENCE attach control: type=\(attach.elementType.rawValue) label=\(attach.label) enabled=\(attach.isEnabled)")
        XCTAssertTrue(attach.isEnabled)
        attach.tap()
        sleep(3)
        shot(app, "11-picker")

        // PhotosPicker is a remote view; its grid is bridged into the host's a11y tree.
        pickFirstPhoto(app)
        sleep(2)

        // Chip: one combined element with the generic image label + "Remove photo".
        let chip = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        let chipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15) || chipButton.waitForExistence(timeout: 5), "pending chip did not appear")
        let chipLabel = chip.exists ? chip.label : chipButton.label
        print("EVIDENCE chip label: \(chipLabel)")
        XCTAssertFalse(chipLabel.contains("/L0/"), "asset identifier leaked into the chip label")
        sleep(1)
        shot(app, "12-chip")

        // Caption + send.
        field.tap()
        sleep(1)
        field.typeText("What is in this photo?")
        sleep(1)
        shot(app, "12b-typed")
        tapSend(app)
        sleep(2)
        shot(app, "12c-after-send-tap")
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'I received your photo'")).firstMatch
        if !reply.waitForExistence(timeout: 20) {
            print("EVIDENCE no reply yet; visible texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
            // Second attempt: the first tap may have only dismissed the keyboard.
            tapSend(app)
        }
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "assistant reply did not render")
        print("EVIDENCE reply: \(reply.label)")
        sleep(2)
        shot(app, "13-sent-echo")

        // Echo tile in the user pane: rendered as a plain image (not a button), generic label.
        let echo = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Image'")).firstMatch
        XCTAssertTrue(echo.waitForExistence(timeout: 5), "echo tile not found")
        print("EVIDENCE echo type: \(echo.elementType.rawValue) (button=9, image=43) label: \(echo.label)")
        XCTAssertNotEqual(echo.elementType, .button, "inline data: echo must not be a button")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Image'")).firstMatch.exists)

        // Relaunch → history round-trip from the stand-in (data URL, no caption).
        app.terminate()
        sleep(1)
        app.launch()
        let replyAgain = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'I received your photo'")).firstMatch
        XCTAssertTrue(replyAgain.waitForExistence(timeout: 30), "history did not load")
        sleep(3)
        shot(app, "14-history")
        let historyEcho = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Image'")).firstMatch
        XCTAssertTrue(historyEcho.waitForExistence(timeout: 5), "history echo tile not found")
        print("EVIDENCE history echo type: \(historyEcho.elementType.rawValue) label: \(historyEcho.label)")
        XCTAssertNotEqual(historyEcho.elementType, .button)
    }

    // MARK: - Helpers

    private func pickFirstPhoto(_ app: XCUIApplication) {
        // Try the picker's own process first, then the bridged tree.
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        let candidates: [XCUIElementQuery] = [
            picker.scrollViews.images, picker.images, picker.cells,
            app.scrollViews.images, app.cells, app.images
        ]
        for query in candidates {
            let first = query.firstMatch
            if first.waitForExistence(timeout: 4) {
                let all = query.allElementsBoundByIndex
                // Skip the SDK's own images (avatar/logo) by preferring elements in the lower 80%.
                let target = all.first { $0.frame.minY > app.frame.height * 0.2 && $0.isHittable } ?? first
                print("EVIDENCE picking photo element: \(target.debugDescription.prefix(200))")
                target.tap()
                return
            }
        }
        XCTFail("no photo cell found in the picker")
    }

    private func composer(_ app: XCUIApplication) -> XCUIElement {
        let byPlaceholder = app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.waitForExistence(timeout: 15) { return byPlaceholder }
        let asField = app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if asField.exists { return asField }
        return app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
    }

    /// The send button carries the `arrow.up` symbol, which XCUITest reads as "Up".
    private func tapSend(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) { notNow.tap() }

        let send = app.buttons.matching(NSPredicate(format: "label == 'Up'")).firstMatch
        guard send.waitForExistence(timeout: 5) else {
            XCTFail("send button not found"); return
        }
        print("EVIDENCE send button: \(send.frame) enabled=\(send.isEnabled)")
        send.tap()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
