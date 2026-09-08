import XCTest

/// Drives the installed Diverge Sample against the forms stand-in (`forms_server.py`) in both
/// conversation flows: validation errors, a dropdown driving a `visible_when` field, a photo
/// into a file field (and *not* into the composer), a ticket attachment, an injected 500,
/// submit → confirmation, a fresh live form, read-only after a newer reply, and a relaunch
/// that keeps submitted forms collapsed and older ones read-only.
final class FormsTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-forms"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let run = try controlCall(["reset": true])["run"] as? String ?? "?"
        print("EVIDENCE \(flow) server run=\(run)")

        let app = launch(flow: flow)

        // All three cards render from history at open.
        let contact = card(app, "Contact form")
        let ticket = card(app, "Support ticket")
        let lead = card(app, "Sales lead")
        XCTAssertTrue(contact.waitForExistence(timeout: 20), "contact card not rendered")
        reveal(app, contact)
        sleep(1)
        shot(app, "\(flow)-10-open")

        // 1. Validation: an empty submit marks every required field; a bad email is called out.
        tapSubmit(app, in: contact)
        let required = app.staticTexts.matching(NSPredicate(format: "label == 'This field is required'"))
        XCTAssertTrue(required.firstMatch.waitForExistence(timeout: 5), "required errors did not appear")
        print("EVIDENCE \(flow) contact required-errors=\(required.count)")
        XCTAssertGreaterThanOrEqual(required.count, 3)
        shot(app, "\(flow)-11-contact-required")

        type(app, key: "name", "Jane Doe")
        type(app, key: "email", "not-an-email")
        type(app, key: "message", "Hello from XCUITest", multiline: true)
        dismissKeyboard(app)
        tapSubmit(app, in: contact)
        let badEmail = app.staticTexts["Enter a valid email address"]
        XCTAssertTrue(badEmail.waitForExistence(timeout: 5), "email error did not appear")
        shot(app, "\(flow)-12-contact-bad-email")

        // 2. Contact submit → confirmation card.
        clearAndType(app, key: "email", "jane@example.com")
        dismissKeyboard(app)
        tapSubmit(app, in: contact)
        let contactDone = app.staticTexts["Thanks, we have received your message."]
        XCTAssertTrue(contactDone.waitForExistence(timeout: 15), "contact confirmation did not render")
        print("EVIDENCE \(flow) contact submitted")
        shot(app, "\(flow)-13-contact-submitted")

        // 3. Custom form: the dropdown drives `claim` visibility (server-compatible cascade).
        reveal(app, lead)
        let claim = field(app, key: "claim", in: lead)
        XCTAssertFalse(claim.exists, "claim must be hidden before a distributor is picked")
        pickDropdown(app, key: "distributor", option: "dhl")
        XCTAssertFalse(claim.exists, "claim must stay hidden for dhl")
        pickDropdown(app, key: "distributor", option: "postnord")
        XCTAssertTrue(claim.waitForExistence(timeout: 5), "claim did not appear for postnord")
        print("EVIDENCE \(flow) visible_when claim shown for postnord, hidden for dhl")
        shot(app, "\(flow)-14-lead-visible-when")

        // 4. Photo into the file field — lands on the field, never in the composer strip.
        reveal(app, lead)
        let addPhoto = lead.buttons["Add photo"].firstMatch
        XCTAssertTrue(addPhoto.waitForExistence(timeout: 5), "file field Add photo missing")
        reveal(app, addPhoto)
        addPhoto.tap()
        sleep(3)
        pickFirstPhoto(app)
        let formChipRemove = lead.buttons["Remove photo"].firstMatch
        XCTAssertTrue(formChipRemove.waitForExistence(timeout: 20), "picked photo did not land on the file field")
        let composerChip = app.otherElements.matching(NSPredicate(format: "label == 'Image'")).firstMatch
        XCTAssertFalse(composerChip.exists, "form pick leaked into the composer strip")
        print("EVIDENCE \(flow) form photo on field=\(formChipRemove.exists) composerChip=\(composerChip.exists)")
        shot(app, "\(flow)-15-lead-photo")

        // 5. Injected 500 → card-level error; the draft survives; retry succeeds.
        type(app, key: "email", "lead@example.com", in: lead)
        type(app, key: "claim", "Parcel arrived damaged", multiline: true, in: lead)
        dismissKeyboard(app)
        _ = try controlCall(["fail_next_action": true])
        tapSubmit(app, in: lead)
        let failed = app.staticTexts["Couldn't send the form. Try again."]
        XCTAssertTrue(failed.waitForExistence(timeout: 15), "500 did not surface on the card")
        print("EVIDENCE \(flow) lead 500 surfaced; claim value kept=\(field(app, key: "claim", in: lead).value as? String ?? "")")
        shot(app, "\(flow)-16-lead-500")
        tapSubmit(app, in: lead)
        let leadDone = app.staticTexts["Thanks — your lead is in."]
        XCTAssertTrue(leadDone.waitForExistence(timeout: 15), "lead confirmation did not render")
        shot(app, "\(flow)-17-lead-submitted")

        // 6. Support ticket with a ticket-level attachment.
        reveal(app, ticket)
        type(app, key: "name", "Jane Doe", in: ticket)
        type(app, key: "email", "jane@example.com", in: ticket)
        type(app, key: "message", "The app crashes on launch", multiline: true, in: ticket)
        dismissKeyboard(app)
        let ticketAdd = ticket.buttons["Add photo"].firstMatch
        XCTAssertTrue(ticketAdd.waitForExistence(timeout: 5), "ticket Add photo missing")
        reveal(app, ticketAdd)
        ticketAdd.tap()
        sleep(3)
        pickFirstPhoto(app)
        XCTAssertTrue(ticket.buttons["Remove photo"].firstMatch.waitForExistence(timeout: 20), "ticket attachment chip missing")
        tapSubmit(app, in: ticket)
        let ticketDone = app.staticTexts["Your ticket has been created."]
        XCTAssertTrue(ticketDone.waitForExistence(timeout: 15), "ticket confirmation did not render")
        print("EVIDENCE \(flow) ticket submitted with attachment")
        shot(app, "\(flow)-18-ticket-submitted")

        // 7. A live reply carrying a fresh contact form; then a newer reply makes it read-only.
        send(app, "please send me a form")
        let liveIntro = app.staticTexts["Here is a fresh form."]
        XCTAssertTrue(liveIntro.waitForExistence(timeout: 20), "live form reply did not render")
        let liveContact = card(app, "Contact form")
        XCTAssertTrue(liveContact.waitForExistence(timeout: 10))
        reveal(app, liveContact)
        XCTAssertTrue(liveContact.buttons["form.submit"].firstMatch.waitForExistence(timeout: 5), "live form not editable")
        shot(app, "\(flow)-19-live-form")

        send(app, "hello")
        XCTAssertTrue(app.staticTexts["Noted."].waitForExistence(timeout: 20), "follow-up reply did not render")
        // The only remaining form is the live contact card, now behind a newer reply: its Submit
        // is replaced by the visible read-only caption. (List rows out of view leave the tree,
        // so query at app scope and scroll the caption in.)
        let readOnly = app.descendants(matching: .any)["form.readOnly"].firstMatch
        XCTAssertTrue(readOnly.waitForExistence(timeout: 10), "read-only caption missing on the older form")
        reveal(app, readOnly)
        XCTAssertEqual(readOnly.label, "This form can no longer be edited")
        XCTAssertFalse(app.buttons["form.submit"].exists, "older form still shows Submit")
        print("EVIDENCE \(flow) older form read-only caption=\(readOnly.exists) submitButtons=\(app.buttons.matching(identifier: "form.submit").count)")
        shot(app, "\(flow)-20-read-only")

        // 8. Relaunch: submitted forms stay collapsed (persisted), the older one stays read-only.
        app.terminate()
        sleep(1)
        let again = launch(flow: flow)
        XCTAssertTrue(composer(again).waitForExistence(timeout: 20))
        let confirmations = again.staticTexts.matching(NSPredicate(
            format: "label IN %@",
            ["Thanks, we have received your message.", "Thanks — your lead is in.", "Your ticket has been created."]
        ))
        var seen = 0
        for _ in 0..<12 {
            seen = confirmations.count
            if seen >= 3 { break }
            again.swipeDown(velocity: .fast)
            usleep(400_000)
        }
        print("EVIDENCE \(flow) relaunch confirmations visible=\(seen)")
        XCTAssertGreaterThanOrEqual(seen, 3, "submitted forms did not stay collapsed after relaunch")
        XCTAssertFalse(again.textFields["form.field.claim"].exists, "lead form editable again after relaunch")
        shot(again, "\(flow)-21-relaunch-submitted")

        let readOnlyAgain = again.staticTexts["This form can no longer be edited"]
        for _ in 0..<12 where !readOnlyAgain.waitForExistence(timeout: 1) {
            again.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(readOnlyAgain.exists, "older form not read-only after relaunch")
        shot(again, "\(flow)-22-relaunch-read-only")
        again.terminate()
    }

    // MARK: - Helpers

    private func launch(flow: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launch()
        XCTAssertTrue(composer(app).waitForExistence(timeout: 20), "composer not found")
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

    /// The card container carries the form title as its accessibility label. Several cards can
    /// share a title (seeded + live contact form) — the newest is the last match.
    private func card(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.otherElements.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.last
            ?? app.otherElements.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func field(_ app: XCUIApplication, key: String, in card: XCUIElement? = nil) -> XCUIElement {
        let scope: XCUIElementQuery = card.map { $0.descendants(matching: .any) } ?? app.descendants(matching: .any)
        let id = "form.field.\(key)"
        let field = scope.matching(identifier: id)
        if field.matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.textField.rawValue)).firstMatch.exists {
            return field.matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.textField.rawValue)).firstMatch
        }
        if field.matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.textView.rawValue)).firstMatch.exists {
            return field.matching(NSPredicate(format: "elementType == %d", XCUIElement.ElementType.textView.rawValue)).firstMatch
        }
        return field.firstMatch
    }

    private func type(_ app: XCUIApplication, key: String, _ text: String, multiline: Bool = false, in card: XCUIElement? = nil) {
        // Move between fields with the keyboard down so the target is never under it.
        dismissKeyboard(app)
        let element = field(app, key: key, in: card)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "field \(key) missing")
        reveal(app, element)
        element.tap()
        element.typeText(text)
    }

    private func clearAndType(_ app: XCUIApplication, key: String, _ text: String) {
        dismissKeyboard(app)
        let element = field(app, key: key)
        reveal(app, element)
        element.tap()
        if let value = element.value as? String, !value.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 2))
        }
        element.typeText(text)
    }

    private func pickDropdown(_ app: XCUIApplication, key: String, option: String) {
        let menu = field(app, key: key)
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "dropdown \(key) missing")
        reveal(app, menu)
        menu.tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "menu option \(option) missing")
        item.tap()
        sleep(1)
    }

    private func tapSubmit(_ app: XCUIApplication, in card: XCUIElement) {
        let submit = card.buttons["form.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "Submit missing in \(card.label)")
        reveal(app, submit)
        submit.tap()
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let field = composer(app)
        reveal(app, field)
        field.tap()
        field.typeText(text)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) { notNow.tap() }
        let sendButton = app.buttons.matching(NSPredicate(format: "label == 'Up'")).firstMatch
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "send button not found")
        sendButton.tap()
    }

    /// Bottom of the conversation viewport: the composer's top edge wherever the keyboard has
    /// pushed it, or (composer hidden behind the keyboard) the SDK's "Done" bar, else the screen.
    private func viewportBottom(_ app: XCUIApplication) -> CGFloat {
        let composerAny = app.descendants(matching: .any)
            .matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if composerAny.exists { return composerAny.frame.minY - 16 }
        let done = app.buttons["form.done"].firstMatch
        if done.exists { return done.frame.minY - 130 }
        return app.frame.maxY - 170
    }

    /// Scrolls until `element` sits fully inside the conversation viewport (List rows off-screen
    /// are not hittable). Drags start in the list's left gutter (x ≈ 12 pt), outside every card,
    /// so a press can never land on a Submit button or a dropdown.
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        guard element.waitForExistence(timeout: 3) else { return }
        let screen = app.frame
        for _ in 0..<12 {
            let frame = element.frame
            let bottom = viewportBottom(app)
            if element.isHittable, frame.minY > screen.minY + 110, frame.maxY < bottom { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            let delta: CGFloat = frame.midY > (screen.minY + 110 + bottom) / 2 ? -0.3 : 0.3
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5 + delta))
            start.press(forDuration: 0.05, thenDragTo: end)
            usleep(600_000)
        }
    }

    /// The SDK's keyboard bar offers "Done" while a form field is focused.
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["form.done"].firstMatch
        guard done.exists || app.keyboards.count > 0 else { return }
        if done.exists {
            done.tap()
        } else {
            app.swipeDown(velocity: .slow) // scrollDismissesKeyboard(.interactively)
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
        _ = XCTWaiter().wait(for: [gone], timeout: 5)
        print("EVIDENCE keyboard Done bar dismissed=\(!done.exists)")
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
