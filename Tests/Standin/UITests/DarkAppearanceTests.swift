import XCTest
import UIKit

/// Drives the installed Diverge Sample against `dark_theme_server.py` in both
/// conversation flows. Colour is the assertion: sample the chat background from a
/// screenshot and assert light (#FFFFFF) vs dark (#1C1C1E).
///
/// Simulator appearance flips go through `POST /__control` (`sim_appearance`) because
/// the UITest bundle is an iOS target and cannot spawn `Process` / `xcrun`.
/// `sim_udid` is `SIM_UDID` or `"booted"` — never a hardcoded device id.
final class DarkAppearanceTests: XCTestCase {

    private let shots = "/tmp/diverge-standin/shots-dark-appearance"
    private let control = URL(string: "http://127.0.0.1:3000/__control")!
    /// Destination UDID when XCTest supplies `SIM_UDID`; otherwise the booted simulator.
    private let simUDID = ProcessInfo.processInfo.environment["SIM_UDID"] ?? "booted"

    /// Light stand-in surface is #FFFFFF; dark is #1C1C1E.
    private let lightLumaMin: CGFloat = 0.85
    private let darkLumaMax: CGFloat = 0.25

    func testTopDown() throws { try run(flow: "topDown") }
    func testBottomUp() throws { try run(flow: "bottomUp") }

    private func run(flow: String) throws {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        print("EVIDENCE sim_udid=\(simUDID)")
        _ = try controlCall(["sim_appearance": "light", "sim_udid": simUDID])

        // --- System light → light palette ---
        _ = try controlCall(["reset": true, "include_dark_theme": true])
        var app = launch(flow: flow, appearance: "system")
        try waitUntilChatReady(app, flow: flow)
        Thread.sleep(forTimeInterval: 1.0)
        assertBackground(app, expectsDark: false, name: "\(flow)-10-system-light")
        print("EVIDENCE \(flow) system light → light palette")

        // --- Flip simulator to dark without relaunch ---
        _ = try controlCall(["sim_appearance": "dark", "sim_udid": simUDID])
        Thread.sleep(forTimeInterval: 1.5)
        assertBackground(app, expectsDark: true, name: "\(flow)-20-system-dark")
        print("EVIDENCE \(flow) system dark → dark palette")
        app.terminate()

        // --- SAMPLE_APPEARANCE=light stays light while simulator is dark ---
        _ = try controlCall([
            "reset": true,
            "include_dark_theme": true,
            "sim_appearance": "dark",
            "sim_udid": simUDID,
        ])
        app = launch(flow: flow, appearance: "light")
        try waitUntilChatReady(app, flow: flow)
        Thread.sleep(forTimeInterval: 1.0)
        assertBackground(app, expectsDark: false, name: "\(flow)-30-forced-light")
        print("EVIDENCE \(flow) forced light while sim dark")
        app.terminate()

        // --- SAMPLE_APPEARANCE=dark stays dark while simulator is light ---
        _ = try controlCall([
            "reset": true,
            "include_dark_theme": true,
            "sim_appearance": "light",
            "sim_udid": simUDID,
        ])
        app = launch(flow: flow, appearance: "dark")
        try waitUntilChatReady(app, flow: flow)
        Thread.sleep(forTimeInterval: 1.0)
        assertBackground(app, expectsDark: true, name: "\(flow)-40-forced-dark")
        print("EVIDENCE \(flow) forced dark while sim light")
        app.terminate()

        // --- No dark_theme block → stays light in dark mode ---
        _ = try controlCall([
            "reset": true,
            "include_dark_theme": false,
            "sim_appearance": "dark",
            "sim_udid": simUDID,
        ])
        app = launch(flow: flow, appearance: "system")
        try waitUntilChatReady(app, flow: flow)
        Thread.sleep(forTimeInterval: 1.0)
        assertBackground(app, expectsDark: false, name: "\(flow)-50-no-dark-theme")
        print("EVIDENCE \(flow) absent dark_theme stays light in dark mode")
        print("EVIDENCE \(flow) done")
        app.terminate()

        _ = try controlCall(["sim_appearance": "light", "sim_udid": simUDID])
    }

    // MARK: - Helpers

    private func waitUntilChatReady(_ app: XCUIApplication, flow: String) throws {
        let unavailable = app.staticTexts["Assistant Unavailable"]
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if unavailable.exists {
                shot(app, "\(flow)-fail-unavailable")
                XCTFail("chat bootstrap failed — is dark_theme_server.py listening on :3000?")
                return
            }
            if app.staticTexts["Local stand-in — dark appearance."].exists { return }
            if app.textFields.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch.exists {
                return
            }
            if app.textViews.matching(NSPredicate(format: "placeholderValue == 'Ask anything'")).firstMatch.exists {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        shot(app, "\(flow)-fail-no-ready")
        print("AX TREE:\n\(app.debugDescription)")
        XCTFail("chat never became ready")
    }

    private func launch(flow: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "ai.askdiverge.sample")
        app.launchEnvironment["SAMPLE_AUTO_TOKEN"] = "host-token"
        app.launchEnvironment["SAMPLE_FLOW"] = flow
        app.launchEnvironment["SAMPLE_STANDIN"] = "1"
        app.launchEnvironment["SAMPLE_APPEARANCE"] = appearance
        app.launch()
        return app
    }

    private func assertBackground(_ app: XCUIApplication, expectsDark: Bool, name: String) {
        let luma = sampleLuma(app, name: name)
        print("EVIDENCE \(name) luma=\(String(format: "%.3f", luma)) expectsDark=\(expectsDark)")
        if expectsDark {
            XCTAssertLessThan(luma, darkLumaMax, "\(name): expected dark background, luma=\(luma)")
        } else {
            XCTAssertGreaterThan(luma, lightLumaMin, "\(name): expected light background, luma=\(luma)")
        }
    }

    /// Average luma of a small patch ~45% down the screen (empty chat surface under header/logo).
    private func sampleLuma(_ app: XCUIApplication, name: String) -> CGFloat {
        let shot = XCUIScreen.main.screenshot()
        let data = shot.pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
        guard let uiImage = UIImage(data: data) else {
            XCTFail("could not decode screenshot"); return -1
        }
        // Re-render through UIKit so pixel (0,0) is top-left (CGImage alone is bottom-left).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: uiImage.size, format: format).image { _ in
            uiImage.draw(at: .zero)
        }
        guard let cgImage = rendered.cgImage else { return -1 }
        let w = cgImage.width
        let h = cgImage.height
        guard let provider = cgImage.dataProvider, let raw = provider.data else { return -1 }
        let ptr = CFDataGetBytePtr(raw)!
        let bpp = max(cgImage.bitsPerPixel / 8, 4)
        let stride = cgImage.bytesPerRow

        let cx = w / 2
        let cy = Int(CGFloat(h) * 0.45)
        let half = 12
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for y in (cy - half)...(cy + half) {
            for x in (cx - half)...(cx + half) {
                guard x >= 0, y >= 0, x < w, y < h else { continue }
                let i = y * stride + x * bpp
                let r = CGFloat(ptr[i]) / 255
                let g = CGFloat(ptr[i + 1]) / 255
                let b = CGFloat(ptr[i + 2]) / 255
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        return count > 0 ? sum / count : -1
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
