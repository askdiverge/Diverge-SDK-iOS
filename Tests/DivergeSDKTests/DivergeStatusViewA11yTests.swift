import XCTest
@_spi(Testing) import DivergeSDK
import DivergeSDKUI

/// Accessibility string-dump contract for VoiceOver (not pixel snapshots).
/// Kept as exact string equality so CI stays stable across OS/simulator versions.
final class DivergeStatusViewA11yTests: XCTestCase {
    override func tearDown() {
        Diverge.reset()
        super.tearDown()
    }

    func testStatusViewNotConfiguredDump() {
        let dump = DivergeStatusView.accessibilityDump(client: nil)
        let expected = [
            "title: Diverge SDK",
            "version: \(Diverge.version)",
            "state: not-configured"
        ].joined(separator: "\n")
        XCTAssertEqual(dump, expected)
    }

    func testStatusViewConfiguredSandboxDump() throws {
        let client = try Diverge.configure(
            DivergeConfiguration(apiKey: "sk_test_a11y", environment: .sandbox)
        )
        let dump = DivergeStatusView.accessibilityDump(client: client)
        let expected = [
            "title: Diverge SDK",
            "version: \(Diverge.version)",
            "environment: sandbox",
            "apiBaseURL: https://sandbox.api.askdiverge.ai"
        ].joined(separator: "\n")
        XCTAssertEqual(dump, expected)
        XCTAssertFalse(dump.contains("sk_test_a11y"), "API key must not appear in a11y dump")
    }

    func testStatusViewAccessibilityLabelsArePresentInViewHierarchy() {
        // Contract for VoiceOver: header + version labels always exist; configured adds env + URL.
        let dump = DivergeStatusView.accessibilityDump(client: nil)
        XCTAssertEqual(
            dump.split(separator: "\n").count,
            3,
            "Not-configured dump should expose title, version, and state"
        )
    }
}
