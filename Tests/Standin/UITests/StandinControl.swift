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

    /// Taps the first photo in the system `PhotosPicker`. The picker is a remote view: its grid
    /// may be bridged into this app's tree or only reachable through the Photos process, so
    /// both are polled. The first open on a fresh simulator builds the photo library behind a
    /// "Loading…" spinner for tens of seconds on a CI runner, so the poll is generous.
    ///
    /// Cells are read from one `snapshot()` per poll rather than from live elements: while the
    /// grid fades in, its cells appear and disappear between queries, and resolving a live
    /// `frame`/`isHittable` on a cell that just vanished is a hard test failure — a snapshot is
    /// consistent, and it throws instead. The tap goes to the cell's coordinate for the same
    /// reason, once two consecutive polls have seen the same grid.
    func pickFirstPhoto(timeout: TimeInterval = 90, file: StaticString = #filePath, line: UInt = #line) {
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        let belowChrome = self.frame.height * 0.2
        var previousCount = -1

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Snapshotting a process that is not running is a hard failure, not an empty tree.
            let roots = picker.state == .notRunning ? [self] : [picker, self]
            var cells: [XCUIElementSnapshot] = []
            var loading = false
            for root in roots {
                guard let tree = try? root.snapshot() else { continue }
                collectPhotoCells(tree, belowChrome: belowChrome, into: &cells, loading: &loading)
            }
            let count = loading ? 0 : cells.count
            if count > 0, count == previousCount, let cell = cells.first {
                let frame = cell.frame
                print("EVIDENCE picking photo cell: id=\(cell.identifier) label=\(cell.label) frame=\(frame) of \(count)")
                self.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                    .tap()
                return
            }
            previousCount = count
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("no photo cell found in the picker within \(Int(timeout))s", file: file, line: line)
    }

    /// Walks one snapshot: flags the picker's "Loading…" state and gathers grid cells — the
    /// picker's own `PXGGridLayout-Info` images, or (older grids) square thumbnails below the
    /// chrome large enough not to be the SDK's avatar or logo.
    private func collectPhotoCells(
        _ node: XCUIElementSnapshot, belowChrome: CGFloat,
        into cells: inout [XCUIElementSnapshot], loading: inout Bool
    ) {
        if node.elementType == .staticText, node.label.hasPrefix("Loading") { loading = true }
        if node.elementType == .image, node.frame.minY > belowChrome {
            let side = node.frame.size
            let square = abs(side.width - side.height) < 2 && side.width >= 60
            if node.identifier == "PXGGridLayout-Info" || square { cells.append(node) }
        }
        for child in node.children {
            collectPhotoCells(child, belowChrome: belowChrome, into: &cells, loading: &loading)
        }
    }
}
