import XCTest

/// Drives the installed Diverge Sample against `livechat_server.py` in both
/// conversation flows: offline toolbar, form `start_livechat` queue, handover /
/// waiting form, AI while waiting, agent join + photo attach, attach-disabled,
/// visitor livechat send, agent-close CSAT, rehydrate Leave + CSAT skip.
final class LivechatTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-livechat"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)

        // --- Offline toolbar ---
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "offline",
            "show_livechat_logo": true,
            "attachments_enabled": true,
            "seed_marker": true,
            "join_after_polls": 99,
        ])
        print("EVIDENCE \(flow) offline start")

        var app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let toolbar = app.buttons["livechat.toolbar"].firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 15), "livechat.toolbar missing")
        XCTAssertEqual(toolbar.value as? String, "offline", "offline toolbar value")
        toolbar.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'offline'")).firstMatch
                .waitForExistence(timeout: 5),
            "offline notice should appear"
        )
        shot(app, "\(flow)-10-offline")
        print("EVIDENCE \(flow) offline toolbar")
        app.terminate()

        // --- Form submit_actions start_livechat (no Talk-to-a-person / no handover) ---
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "live",
            "show_livechat_logo": true,
            "attachments_enabled": true,
            "seed_marker": false,
            "seed_start_livechat_form": true,
            "join_after_polls": 99,
        ])
        print("EVIDENCE \(flow) form start_livechat start")
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let startFormEmail = app.textFields["form.field.email"].firstMatch
        XCTAssertTrue(startFormEmail.waitForExistence(timeout: 20), "start_livechat form email field missing")
        XCTAssertTrue(
            typeIntoFormField(app, identifier: "form.field.email", text: "form-queue@example.com"),
            "start_livechat form email must accept focus"
        )
        dismissKeyboard(app)
        let formSubmit = app.buttons["form.submit"].firstMatch
        XCTAssertTrue(formSubmit.waitForExistence(timeout: 5), "form.submit missing")
        revealAboveComposer(formSubmit, in: app)
        formSubmit.tap()
        let formQueueNote = app.descendants(matching: .any)["livechat.note"].firstMatch
        XCTAssertTrue(formQueueNote.waitForExistence(timeout: 20), "queue note missing after form start_livechat")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'queue'")).firstMatch.exists
                || "\(formQueueNote.label)".lowercased().contains("queue"),
            "queued note text should mention queue after form start"
        )
        XCTAssertFalse(
            app.buttons["livechat.humanAgentPrompt"].exists,
            "Talk-to-a-person marker must not be required for form start_livechat"
        )
        var actionHits: [[String: Any]] = []
        var handoverHits: [[String: Any]] = []
        for _ in 0..<10 {
            let afterForm = try controlCall([:])
            actionHits = afterForm["action_hits"] as? [[String: Any]] ?? []
            handoverHits = afterForm["handover_hits"] as? [[String: Any]] ?? []
            if !actionHits.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(actionHits.isEmpty, "POST /actions should have been recorded")
        XCTAssertTrue(handoverHits.isEmpty, "form start_livechat must not POST /livechat/handover")
        sendMessage(app, "Still with AI after form")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AI still here'")).firstMatch
                .waitForExistence(timeout: 25),
            "AI should reply while waiting after form-started queue"
        )
        shot(app, "\(flow)-15-form-start-livechat")
        print("EVIDENCE \(flow) form start_livechat queued + AI; handover_hits=\(handoverHits.count)")
        app.terminate()

        // --- Handover → queue → AI while waiting → agent join ---
        // join_after_polls stays high so we can assert AI-while-waiting; then join_agent.
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "live",
            "show_livechat_logo": true,
            "attachments_enabled": true,
            "seed_marker": true,
            "seed_start_livechat_form": false,
            "join_after_polls": 99,
        ])
        print("EVIDENCE \(flow) live start")

        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        let liveToolbar = app.buttons["livechat.toolbar"].firstMatch
        XCTAssertTrue(liveToolbar.waitForExistence(timeout: 15))
        XCTAssertEqual(liveToolbar.value as? String, "available")

        let prompt = app.buttons["livechat.humanAgentPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15), "human agent marker CTA missing")
        reveal(prompt, in: app)
        prompt.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let queueNote = app.descendants(matching: .any)["livechat.note"].firstMatch
        XCTAssertTrue(queueNote.waitForExistence(timeout: 15), "queue note missing")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'queue'")).firstMatch.exists
                || "\(queueNote.label)".lowercased().contains("queue"),
            "queued note text should mention queue"
        )
        shot(app, "\(flow)-20-queued")
        print("EVIDENCE \(flow) queued")

        // Handover must carry native client_context (os at minimum).
        var handoverOS: String?
        for _ in 0..<12 {
            let afterHandover = try controlCall([:])
            let hits = afterHandover["handover_hits"] as? [[String: Any]] ?? []
            if let body = hits.last?["body"] as? [String: Any],
               let ctx = body["client_context"] as? [String: Any],
               let os = ctx["os"] as? String
            {
                handoverOS = os
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertEqual(handoverOS, "iOS", "handover client_context.os should be iOS; got \(String(describing: handoverOS))")
        print("EVIDENCE \(flow) handover client_context.os=\(handoverOS ?? "nil")")

        // Waiting-room session form
        let waitingForm = app.descendants(matching: .any)["livechat.waitingForm"].firstMatch
        XCTAssertTrue(waitingForm.waitForExistence(timeout: 20), "waiting form card missing")
        reveal(waitingForm, in: app)
        shot(app, "\(flow)-22-waiting-form")
        print("EVIDENCE \(flow) waiting form visible")

        // Ignore: leave the form alone — form_hits must stay empty before Save
        let hitsBeforeSave = (try controlCall([:])["form_hits"] as? [[String: Any]] ?? []).count
        XCTAssertEqual(hitsBeforeSave, 0, "ignoring the waiting form must not PATCH /forms/.../values")

        // Save email details while still queued.
        // topDown places the waiting-form footer flush against the composer; XCUITest cannot
        // reliably focus `form.field.email` there. bottomUp covers the Save → PATCH path.
        if flow == "bottomUp" {
            XCTAssertTrue(
                typeIntoFormField(app, identifier: "form.field.email", text: "shopper@example.com"),
                "waiting form email must accept focus on bottomUp"
            )
            dismissKeyboard(app)
            let saveButton = app.buttons["livechat.waitingForm.save"].firstMatch
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button missing")
            revealAboveComposer(saveButton, in: app)
            XCTAssertTrue(saveButton.isEnabled, "Save should enable once a field has a value")
            saveButton.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["livechat.waitingForm.saved"].firstMatch
                    .waitForExistence(timeout: 15),
                "Details saved caption missing after Save"
            )
            var formHits: [[String: Any]] = []
            for _ in 0..<10 {
                let afterSave = try controlCall([:])
                formHits = afterSave["form_hits"] as? [[String: Any]] ?? []
                if !formHits.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.3)
            }
            XCTAssertFalse(formHits.isEmpty, "PATCH /forms/.../values should have been recorded")
            let formAuth = (formHits.last?["auth"] as? String) ?? ""
            XCTAssertTrue(formAuth.hasPrefix("Bearer "), "form PATCH must send Bearer; got \(formAuth)")
            let formBody = formHits.last?["body"] as? [String: Any] ?? [:]
            let formValues = formBody["values"] as? [String: Any] ?? [:]
            XCTAssertEqual(formValues["email"] as? String, "shopper@example.com", "PATCH values.email")
            XCTAssertTrue(queueNote.exists || waitingForm.exists, "visitor should stay in queue after Save")
            shot(app, "\(flow)-23-waiting-form-saved")
            print("EVIDENCE \(flow) waiting form saved auth=\(formAuth)")
        } else {
            print("EVIDENCE \(flow) waiting form Save exercised on bottomUp only (footer focus)")
            shot(app, "\(flow)-23-waiting-form-visible-only")
        }

        // AI still answers while waiting (after Save)
        sendMessage(app, "Still with AI")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AI still here'")).firstMatch
                .waitForExistence(timeout: 25),
            "AI should reply while waiting"
        )
        shot(app, "\(flow)-21-ai-while-waiting")
        print("EVIDENCE \(flow) AI while waiting after form save")

        // Scripted agent join (does not wipe history)
        _ = try controlCall(["join_agent": true])

        let agentName = app.descendants(matching: .any)["livechat.agentName"].firstMatch
        XCTAssertTrue(agentName.waitForExistence(timeout: 30), "agent name missing after join")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
                .waitForExistence(timeout: 10)
                || "\(agentName.label)".contains("Alice"),
            "agent display name should show"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hi, I'm Alice")).firstMatch
                .waitForExistence(timeout: 15),
            "agent greeting missing"
        )
        let waitingFormGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: waitingForm
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [waitingFormGone], timeout: 15),
            .completed,
            "waiting form must hide after agent join"
        )
        let typing = app.descendants(matching: .any)["livechat.agentTyping"].firstMatch
        XCTAssertTrue(typing.waitForExistence(timeout: 10), "agent typing indicator missing after join")
        _ = try controlCall(["set_typing": false])
        let typingGone = NSPredicate(format: "exists == false")
        let typingCleared = XCTNSPredicateExpectation(predicate: typingGone, object: typing)
        XCTAssertEqual(
            XCTWaiter.wait(for: [typingCleared], timeout: 15),
            .completed,
            "agent typing should clear after set_typing false"
        )
        shot(app, "\(flow)-30-agent-joined")
        print("EVIDENCE \(flow) agent joined + typing cleared + waiting form gone")

        // Attach + send a photo while the agent session is active (attachments_enabled).
        let attach = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'attach' OR identifier CONTAINS[c] 'attach'")).firstMatch
        XCTAssertTrue(attach.waitForExistence(timeout: 10), "attach control missing while attachments_enabled")
        XCTAssertTrue(attach.isEnabled, "attach should be enabled when livechat.attachments_enabled")
        attach.tap()
        Thread.sleep(forTimeInterval: 2)
        pickFirstPhoto(app)
        let chip = app.otherElements.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        let chipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Remove photo'")).firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 20) || chipButton.waitForExistence(timeout: 5),
            "pending photo chip missing after pick"
        )
        sendMessage(app, "Photo for Alice", preferring: [
            "Message Alice Jensen…",
            "Message the AI assistant while you wait…",
            "Ask anything",
        ])
        var sawImagePart = false
        for _ in 0..<12 {
            let evidencePhoto = (try? String(contentsOfFile: "/tmp/diverge-standin/livechat-evidence.jsonl", encoding: .utf8)) ?? ""
            if evidencePhoto.contains("\"event\": \"livechat_send\"")
                && evidencePhoto.contains("image_parts")
                && evidencePhoto.contains("data_len")
                && evidencePhoto.contains("Bearer ")
            {
                // Prefer a non-empty image payload in the latest evidence lines.
                if evidencePhoto.contains("\"data_len\": 0") == false || evidencePhoto.range(of: #"\"data_len\": [1-9]"#, options: .regularExpression) != nil {
                    sawImagePart = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(sawImagePart, "livechat_send evidence should include a non-empty image part + Bearer")
        shot(app, "\(flow)-35-livechat-photo")
        print("EVIDENCE \(flow) livechat photo send")

        // Visitor send goes to livechat endpoint
        sendMessage(app, "Hello Alice", preferring: [
            "Message Alice Jensen…",
            "Message the AI assistant while you wait…",
            "Ask anything",
        ])
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Hello Alice'")).firstMatch
                .waitForExistence(timeout: 15),
            "visitor livechat message should render"
        )
        // Confirm the stand-in received the livechat POST (not the AI route).
        let evidence = try String(contentsOfFile: "/tmp/diverge-standin/livechat-evidence.jsonl", encoding: .utf8)
        XCTAssertTrue(evidence.contains("\"event\": \"livechat_send\""), "livechat_send missing from evidence")
        XCTAssertTrue(evidence.contains("Hello Alice"), "Hello Alice missing from livechat_send evidence")
        shot(app, "\(flow)-40-visitor-send")
        print("EVIDENCE \(flow) visitor livechat send")
        app.terminate()

        // Attach control disabled when config says attachments_enabled: false (active session).
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "live",
            "attachments_enabled": false,
            "force_status": "active",
            "seed_marker": false,
            "seed_start_livechat_form": false,
        ])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
                .waitForExistence(timeout: 20),
            "active session should rehydrate for attach-disabled check"
        )
        let attachDisabled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] 'attach' OR identifier CONTAINS[c] 'attach'")).firstMatch
        if attachDisabled.waitForExistence(timeout: 5) {
            XCTAssertFalse(attachDisabled.isEnabled, "attach must be disabled when attachments_enabled is false")
        } else {
            // Hidden is also acceptable.
            print("EVIDENCE \(flow) attach control absent when attachments_enabled false")
        }
        shot(app, "\(flow)-36-attach-disabled")
        print("EVIDENCE \(flow) attach disabled while active")
        app.terminate()

        // Resume agent-close CSAT path on a fresh active session.
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "live",
            "attachments_enabled": true,
            "force_status": "active",
            "seed_marker": false,
            "seed_start_livechat_form": false,
        ])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
                .waitForExistence(timeout: 20),
            "active session for CSAT path"
        )

        // Agent-initiated close: final message + ended note + CSAT overlay.
        _ = try controlCall(["close_agent": true])
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Thanks, closing now'")).firstMatch
                .waitForExistence(timeout: 20),
            "agent closing message missing on closed edge"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has ended'")).firstMatch
                .waitForExistence(timeout: 15),
            "ended note missing after agent close"
        )
        let csatScore = app.buttons["rating.score.5"].firstMatch
        XCTAssertTrue(csatScore.waitForExistence(timeout: 15), "CSAT overlay missing after agent close")
        shot(app, "\(flow)-45-agent-close-csat")
        print("EVIDENCE \(flow) agent-initiated close + CSAT")
        csatScore.tap()
        // Score 5 dismisses without feedback step — wait for overlay gone, then assert wire hit.
        let overlayGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: csatScore
        )
        XCTAssertEqual(XCTWaiter.wait(for: [overlayGone], timeout: 10), .completed, "CSAT should dismiss after submitting 5")
        var feedbackHits: [[String: Any]] = []
        for _ in 0..<10 {
            let afterSubmit = try controlCall([:])
            feedbackHits = afterSubmit["feedback_hits"] as? [[String: Any]] ?? []
            if !feedbackHits.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(feedbackHits.isEmpty, "POST /livechat/feedback should have been recorded")
        let auth = (feedbackHits.last?["auth"] as? String) ?? ""
        XCTAssertTrue(auth.hasPrefix("Bearer "), "feedback must send Bearer; got \(auth)")
        print("EVIDENCE \(flow) CSAT submit auth=\(auth)")
        // Chat Close after CSAT must not hit conversation /rate
        tapChatClose(app)
        Thread.sleep(forTimeInterval: 1.0)
        let afterClose = try controlCall([:])
        let rateHits = afterClose["rate_hits"] as? [[String: Any]] ?? []
        XCTAssertTrue(rateHits.isEmpty, "Chat Close after livechat CSAT must not POST /rate")
        print("EVIDENCE \(flow) Chat Close skipped /rate after CSAT")
        app.terminate()

        // --- Rehydration into an already-active session ---
        _ = try controlCall([
            "reset": true,
            "livechat_enabled": true,
            "availability_status": "live",
            "attachments_enabled": true,
            "force_status": "active",
            "seed_marker": false,
            "seed_start_livechat_form": false,
        ])
        app = launch(flow: flow)
        try waitUntilChatReady(app, flow: flow)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch
                .waitForExistence(timeout: 20),
            "rehydration should show the agent name"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Hi, I'm Alice")).firstMatch
                .waitForExistence(timeout: 15),
            "rehydration should replay seeded livechat messages"
        )
        let rehydratedToolbar = app.buttons["livechat.toolbar"].firstMatch
        XCTAssertTrue(rehydratedToolbar.waitForExistence(timeout: 10))
        XCTAssertTrue(
            rehydratedToolbar.label.contains("Leave") || rehydratedToolbar.label.lowercased().contains("leave"),
            "rehydrated active session should offer Leave; got \(rehydratedToolbar.label)"
        )
        shot(app, "\(flow)-60-rehydrate-active")
        print("EVIDENCE \(flow) rehydrate active")

        // Confirm Leave → CSAT → scale Skip (no POST)
        rehydratedToolbar.tap()
        let leaveConfirm = app.buttons["Leave"].firstMatch
        XCTAssertTrue(leaveConfirm.waitForExistence(timeout: 5), "Leave confirmation action missing")
        leaveConfirm.tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has ended'")).firstMatch
                .waitForExistence(timeout: 15),
            "ended note missing after confirmed Leave"
        )
        let leaveCSAT = app.buttons["rating.score.4"].firstMatch
        XCTAssertTrue(leaveCSAT.waitForExistence(timeout: 15), "CSAT overlay missing after Leave")
        let hitsBeforeSkip = (try controlCall([:])["feedback_hits"] as? [[String: Any]] ?? []).count
        app.buttons["rating.skip"].firstMatch.tap()
        let skipGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: leaveCSAT
        )
        XCTAssertEqual(XCTWaiter.wait(for: [skipGone], timeout: 10), .completed, "CSAT should dismiss on scale Skip")
        let hitsAfterSkip = (try controlCall([:])["feedback_hits"] as? [[String: Any]] ?? []).count
        XCTAssertEqual(hitsAfterSkip, hitsBeforeSkip, "scale Skip must not POST /livechat/feedback")
        // Chat stays open — welcome/agent chrome still visible
        XCTAssertTrue(
            app.staticTexts["How can I help?"].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Alice'")).firstMatch.exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'has ended'")).firstMatch.exists,
            "chat should stay open after CSAT skip"
        )
        shot(app, "\(flow)-50-leave-csat-skip")
        print("EVIDENCE \(flow) leave confirmed + CSAT skip")
        print("EVIDENCE \(flow) done")
        app.terminate()
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        let formDone = app.buttons["form.done"].firstMatch
        if formDone.waitForExistence(timeout: 1) {
            formDone.tap()
            return
        }
        if app.keyboards.buttons["Done"].waitForExistence(timeout: 1) {
            app.keyboards.buttons["Done"].tap()
            return
        }
        // Tap above the keyboard / composer to resign first responder.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        Thread.sleep(forTimeInterval: 0.2)
    }

    /// Focus + type into a form text field. Returns false if the field is missing.
    @discardableResult
    private func typeIntoFormField(_ app: XCUIApplication, identifier: String, text: String) -> Bool {
        dismissKeyboard(app)
        let field = app.textFields[identifier].firstMatch
        guard field.waitForExistence(timeout: 10) else { return false }
        revealAboveComposer(field, in: app)
        field.tap()
        Thread.sleep(forTimeInterval: 0.3)
        field.typeText(text)
        return true
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

    /// SDK close button (conversation rating path) — must not re-prompt CSAT or /rate after livechat CSAT.
    private func tapChatClose(_ app: XCUIApplication) {
        let byId = app.descendants(matching: .any).matching(identifier: "rating.close").firstMatch
        if byId.waitForExistence(timeout: 3) {
            byId.tap()
            return
        }
        // Fallback: toolbar close
        let close = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).firstMatch
        if close.exists { close.tap() }
    }

    // MARK: - Helpers

    private func waitUntilChatReady(_ app: XCUIApplication, flow: String) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is livechat_server.py listening on :3000?")
                return
            }
            if app.buttons["livechat.toolbar"].exists { return }
            if app.staticTexts["How can I help?"].exists { return }
            if app.buttons["livechat.humanAgentPrompt"].exists { return }
            if app.textFields["form.field.email"].exists { return }
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

    /// Prefer chat-composer placeholders; never fall back to the Sample landing "Session token" field.
    private func composer(
        _ app: XCUIApplication,
        preferring placeholders: [String] = [
            "Message the AI assistant while you wait…",
            "Ask anything",
            "Message Alice Jensen…",
        ]
    ) -> XCUIElement {
        for p in placeholders {
            let tv = app.textViews.matching(NSPredicate(format: "placeholderValue == %@", p)).firstMatch
            if tv.waitForExistence(timeout: 2) { return tv }
            let tf = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", p)).firstMatch
            if tf.exists { return tf }
        }
        // Last resort: bottom-most text field that is not the Sample token/page fields.
        let fields = app.textFields.allElementsBoundByIndex.filter {
            let ph = $0.placeholderValue ?? ""
            let label = $0.label
            return !label.contains("Session token")
                && !label.contains("Page")
                && !ph.contains("Session token")
                && !ph.contains("Page")
        }
        if let bottom = fields.max(by: { $0.frame.minY < $1.frame.minY }) {
            return bottom
        }
        return app.textFields["Ask anything"].firstMatch
    }

    private func sendMessage(
        _ app: XCUIApplication,
        _ text: String,
        preferring placeholders: [String] = [
            "Message the AI assistant while you wait…",
            "Ask anything",
            "Message Alice Jensen…",
        ]
    ) {
        let field = composer(app, preferring: placeholders)
        XCTAssertTrue(field.waitForExistence(timeout: 10), "composer missing for \(text)")
        field.tap()
        // Clear leftover draft (prior failed send leaves typed text as the field value).
        if let value = field.value as? String,
           !value.isEmpty,
           !placeholders.contains(value),
           value != text
        {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 4)
            field.typeText(deletes)
        }
        field.typeText(text)
        tapSend(app)
        Thread.sleep(forTimeInterval: 0.6)
        // First tap often only dismisses the keyboard (PhotoTests pattern).
        if (field.value as? String) == text || (field.value as? String)?.contains(text) == true {
            tapSend(app)
        }
    }

    /// The send button carries the `arrow.up` symbol, which XCUITest reads as "Up".
    private func tapSend(_ app: XCUIApplication) {
        let send = app.buttons.matching(NSPredicate(format: "label == 'Up' || label == 'arrow.up'")).firstMatch
        guard send.waitForExistence(timeout: 5) else {
            XCTFail("send button not found"); return
        }
        print("EVIDENCE send button enabled=\(send.isEnabled) frame=\(send.frame)")
        send.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        revealAboveComposer(element, in: app)
    }

    /// Scrolls until `element` sits above the composer (List rows under the input are not hittable).
    private func revealAboveComposer(_ element: XCUIElement, in app: XCUIApplication) {
        guard element.waitForExistence(timeout: 3) else { return }
        let screen = app.frame
        for _ in 0..<14 {
            let frame = element.frame
            let bottom = composerTop(app)
            if element.isHittable, frame.height > 8, frame.minY > screen.minY + 100, frame.maxY < bottom {
                return
            }
            // Drag in the left gutter so we don't accidentally tap Save / attach.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
            let delta: CGFloat = frame.midY > (screen.minY + 100 + bottom) / 2 ? -0.28 : 0.28
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5 + delta))
            start.press(forDuration: 0.05, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.35)
        }
    }

    private func composerTop(_ app: XCUIApplication) -> CGFloat {
        let placeholders = [
            "Message the AI assistant while you wait…",
            "Ask anything",
            "Message Alice Jensen…",
        ]
        for p in placeholders {
            let field = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", p)).firstMatch
            if field.exists { return field.frame.minY - 12 }
            let tv = app.textViews.matching(NSPredicate(format: "placeholderValue == %@", p)).firstMatch
            if tv.exists { return tv.frame.minY - 12 }
        }
        let done = app.buttons["form.done"].firstMatch
        if done.exists { return done.frame.minY - 12 }
        return app.frame.maxY - 170
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
