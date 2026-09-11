import XCTest

/// Drives the installed Diverge Sample against the upload-prompt stand-in
/// (`upload_prompt_server.py`) and checks the card → picker → chip → send → history path
/// in both conversation flows.
final class UploadPromptTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-upload-prompt"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        StandinControl.reset()
    }

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launch()

        let field = app.composer()
        XCTAssertTrue(field.waitForExistence(timeout: 20), "composer not found")

        // Seeded history text + the upload-prompt card.
        let seed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'receipt'")).firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 20), "seeded assistant text not rendered")
        let prompt = uploadPrompt(app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "upload prompt card not found on open")
        print("EVIDENCE \(flow) open prompt label=\(prompt.label) enabled=\(prompt.isEnabled)")
        XCTAssertTrue(prompt.isEnabled)
        sleep(1)
        shot(app, "\(flow)-10-open")

        // Live arrival: a text-only send makes the stand-in stream a reply that ends with the
        // marker as a `part` and then holds the stream open (TAIL_DELAY) before `done`. The
        // card must appear in the new reply, be disabled while the turn streams, and enable
        // once `done` lands.
        field.tap()
        field.typeText("hello")
        app.tapSend()
        let liveReply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'please add a photo'")).firstMatch
        XCTAssertTrue(liveReply.waitForExistence(timeout: 20), "text-only reply did not render")
        // The live card is the newest one on screen (the seed card may have scrolled off in
        // topDown, and earlier runs may have left more cards in the stand-in's history).
        var liveCards = uploadPrompts(app).allElementsBoundByIndex
        for _ in 0..<20 where liveCards.count < 2 || liveCards.last?.frame.minY ?? 0 <= liveReply.frame.minY {
            usleep(300_000)
            liveCards = uploadPrompts(app).allElementsBoundByIndex
        }
        guard let livePrompt = liveCards.last, livePrompt.frame.minY > liveReply.frame.minY else {
            XCTFail("live upload prompt card not found beneath the streamed reply (cards on screen: \(liveCards.count))")
            return
        }
        let duringStream = livePrompt.isEnabled
        print("EVIDENCE \(flow) live card enabled while streaming=\(duringStream)")
        shot(app, "\(flow)-10b-live-streaming")
        XCTAssertFalse(duringStream, "card must be disabled while the reply streams")
        let enabled = NSPredicate(format: "isEnabled == true")
        let settled = XCTNSPredicateExpectation(predicate: enabled, object: livePrompt)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 15), .completed, "card did not enable after done")
        print("EVIDENCE \(flow) live card enabled after done=\(livePrompt.isEnabled)")
        shot(app, "\(flow)-10c-live-settled")

        // Tap the (seeded) card → shared PhotosPicker.
        prompt.tap()
        sleep(3)
        shot(app, "\(flow)-11-picker")
        pickFirstPhoto(app)
        sleep(2)

        // Chip lands the same way as the composer attach path.
        let chip = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        let chipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 15) || chipButton.waitForExistence(timeout: 5),
            "pending chip did not appear after prompt tap"
        )
        sleep(1)
        shot(app, "\(flow)-12-chip")

        app.tapSend()
        let reply = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'I received your photo'")).firstMatch
        if !reply.waitForExistence(timeout: 20) {
            app.tapSend()
        }
        XCTAssertTrue(reply.waitForExistence(timeout: 30), "assistant reply after photo send did not render")
        sleep(2)
        shot(app, "\(flow)-13-sent")

        // Relaunch → history still carries the seeded upload prompt (may sit above the viewport
        // once later turns have grown the conversation — scroll up until it is found).
        app.terminate()
        sleep(1)
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launch()
        XCTAssertTrue(app.composer().waitForExistence(timeout: 20))
        let replyAgain = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'I received your photo'")).firstMatch
        XCTAssertTrue(replyAgain.waitForExistence(timeout: 20), "history did not reload the photo reply")
        var promptAgain = uploadPrompt(app)
        for _ in 0..<12 where !promptAgain.waitForExistence(timeout: 1) {
            app.swipeDown(velocity: .fast)
            promptAgain = uploadPrompt(app)
        }
        XCTAssertTrue(promptAgain.waitForExistence(timeout: 5), "upload prompt missing after relaunch/history")
        sleep(2)
        shot(app, "\(flow)-14-history")
        print("EVIDENCE \(flow) history prompt label=\(promptAgain.label)")
        app.terminate()
    }

    // MARK: - Helpers

    private func uploadPrompts(_ app: XCUIApplication) -> XCUIElementQuery {
        // VoiceOver label is the prompt line; under the CLI String Catalog the key may echo,
        // so match either the English copy or the resource key.
        app.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'Add a photo' OR label CONTAINS[c] 'imageUpload.prompt' OR label CONTAINS[c] 'photo so I can help'"
        ))
    }

    private func uploadPrompt(_ app: XCUIApplication) -> XCUIElement {
        uploadPrompts(app).firstMatch
    }

    private func pickFirstPhoto(_ app: XCUIApplication) {
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        let candidates: [XCUIElementQuery] = [
            picker.scrollViews.images, picker.images, picker.cells,
            app.scrollViews.images, app.cells, app.images
        ]
        for query in candidates {
            let first = query.firstMatch
            if first.waitForExistence(timeout: 4) {
                let all = query.allElementsBoundByIndex
                let target = all.first { $0.frame.minY > app.frame.height * 0.2 && $0.isHittable } ?? first
                target.tap()
                return
            }
        }
        XCTFail("no photo cell found in the picker")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }
}
