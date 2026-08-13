import XCTest
@_spi(Testing) import DivergeSDK
import DivergeSDKUI

/// Accessibility dump contract for VoiceOver — kept as exact string equality.
final class DivergeStatusViewSnapshotTests: XCTestCase {
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
            Configuration(apiKey: "sk_test_snapshot", environment: .sandbox)
        )
        let dump = DivergeStatusView.accessibilityDump(client: client)
        let expected = [
            "title: Diverge SDK",
            "version: \(Diverge.version)",
            "environment: sandbox",
            "apiBaseURL: https://sandbox.api.askdiverge.ai"
        ].joined(separator: "\n")
        XCTAssertEqual(dump, expected)
        XCTAssertFalse(dump.contains("sk_test_snapshot"), "API key must not appear in a11y dump")
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
