import Foundation
import XCTest

/// POSTs `{"reset":true}` to the stand-in on `:3000` so each XCTest method starts from seed.
enum StandinControl {
    static func reset(timeout: TimeInterval = 2) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3000/__control")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"reset":true}"#.utf8)
        request.timeoutInterval = timeout
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + timeout)
    }
}

/// Shared Sample-chat element lookups so every suite drives the composer the same way.
extension XCUIApplication {

    /// The composer text control. SwiftUI backs it with a text view on iOS 18+ and a text field on
    /// older / other hosts, so both are tried before falling back to the first text control.
    func composer() -> XCUIElement {
        let byPlaceholder = self.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if byPlaceholder.waitForExistence(timeout: 15) { return byPlaceholder }
        let asField = self.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch
        if asField.exists { return asField }
        return self.textViews.firstMatch.exists ? self.textViews.firstMatch : self.textFields.firstMatch
    }

    /// Taps the composer send button by its `chat.send` identifier. Dismisses the Simulator's
    /// "Not Now" keyboard-suggestion sheet first when it is in the way. Positional heuristics are
    /// deliberately avoided — the software keyboard's dictation key sits in the same corner.
    func tapSend(file: StaticString = #filePath, line: UInt = #line) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 1) { notNow.tap() }

        let send = self.buttons["chat.send"].firstMatch
        guard send.waitForExistence(timeout: 5) else {
            XCTFail("send button (chat.send) not found", file: file, line: line)
            return
        }
        print("EVIDENCE send button: \(send.frame) enabled=\(send.isEnabled)")
        send.tap()
    }
}
